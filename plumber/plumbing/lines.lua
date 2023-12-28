-- name: lines
-- args: none
-- inputs: 1
-- outputs: 1

local function checkActive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

local preserve = (...) == "buffer"
local buffer = ""

while true do
  local result = plumber.waitInput(1)
  if result then
    repeat
      local nnl = result:find("\n") or (not preserve and #result + 1)
      if nnl then
        local line = result:sub(1, nnl - 1)
        result = result:sub(nnl+1)
        plumber.write(line.."\n")
        buffer = ""
      else
        buffer = buffer .. nnl
      end
    until #result == 0
  end
  if not checkActive() and not result then break end
end

if buffer and #buffer > 0 then plumber.write(buffer .. "\n") end
