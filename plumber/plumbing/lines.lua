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
  if result then plumber.write(result.."\n") end
  if not checkInactive() and not result then break end
end
