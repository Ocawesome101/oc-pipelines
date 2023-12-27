-- name: lines
-- args: none
-- inputs: 1
-- outputs: 1

local function checkInactive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

while true do
  local result = plumber.waitInput(1)
  if result then
    repeat
      local nnl = result:find("\n") or (#result + 1)
      local line = result:sub(1, nnl - 1)
      result = result:sub(nnl+1)
      plumber.write(line.."\n")
    until #result == 0
  end
  if not checkInactive() and not result then break end
end
