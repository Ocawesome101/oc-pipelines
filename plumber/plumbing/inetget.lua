-- name: inetget
-- args: url? softfail?
-- inputs: data?
-- outputs: data
-- Retrieve data from one or more network URLs.
-- Interjects data as tables if in loop mode.

local url, softfail = ...
if url == "softfail" then
  url = softfail
  softfail = true
else
  softfail = softfail == "softfail"
end
local loop = not url

local function checkActive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

if #plumber.getInputs() == 0 and not url then
  if softfail then return end
  error("inetget: must be given either a url OR an input", 0)
end

local caddr = component.list("internet", true)()
if not caddr then
  if softfail then return end
  error("inetget: no internet card found", 0)
end

local inet = component.proxy(caddr)
if not inet.isHttpEnabled() then
  if softfail then return end
  error("inetget: http is not enabled", 0)
end

local queue = {url}
local working

while checkActive() or working do
  coroutine.yield(0)
  if loop then
    if not url and #queue == 0 and not working then
      plumber.waitInputs()
    end
    local inputs = plumber.pollInputs()
    if inputs then
      for _, input in pairs(inputs) do
        queue[#queue+1] = plumber.pollInput(input)
      end
    end
  end
  if working then
    local data = working.read()
    if not data then
      if loop then plumber.write({"done"}) end
      working.close()
      working = nil
    elseif #data > 0 then
      plumber.write(data)
    end
  elseif #queue > 0 then
    working = inet.request(queue[1])
    repeat
      local result, err = working.finishConnect()
      if not result and err then
        if not softfail then error(err, 0) end
        working = nil
        plumber.write({queue[1], "failed"})
      end
    until result or err
    if loop then plumber.write({queue[1], working.response()}) end
    table.remove(queue, 1)
  end
  if not loop and not working then break end
end

if working then working.close() end
