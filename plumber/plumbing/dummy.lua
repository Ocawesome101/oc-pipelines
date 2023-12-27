-- name: dummy
-- args: none
-- inputs: 1
-- outputs: any

local function checkActive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

while true do
  local result = plumber.waitInput(1)
  plumber.write(result)
  if not checkActive() and not result then break end
end
