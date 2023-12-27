-- name: dummy
-- args: none
-- inputs: 1
-- outputs: any

local args = {...}

local function checkActive()
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
  local n = plumber.pollInputs()
  if n and #n > 0 then return true end
end

for i=1, #args do
  plumber.write(args[i])
end

while checkActive() do
  local result = plumber.waitInput(1)
  plumber.write(result)
end
