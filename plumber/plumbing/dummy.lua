local function checkInactive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

while true do
  if checkInactive() then break end
  coroutine.yield(0)
  plumber.write(plumber.waitInput(1))
end
