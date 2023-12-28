-- name: writer
-- args: path
-- inputs: data
-- outputs: none
-- Write data to one or more files.  Supports input from 'inetget' otherwise
-- writes to the supplied file path.

local function checkActive()
  for _, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

local base = (...)

local file = ""
local handle

while checkActive() do
  local data = plumber.waitInput(1)
  if type(data) == "table" then
    file = data[1]
    if handle then handle:close() handle = nil end
  elseif not handle then
    local path = (base .. "/" .. file):gsub("/+", "/")
    local handle, err = fs.open(path, "w")
    if not handle then
      error("failed opening path for writing: " .. err)
    end
    handle:write(data)
  else
    handle:write(data)
  end
end

if handle then handle:close() end
