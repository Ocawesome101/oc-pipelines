local function checkInactive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

while true do
  local result = plumber.waitInput(1)
  plumber.write(result)
  if not checkInactive() and not result then break end
end
