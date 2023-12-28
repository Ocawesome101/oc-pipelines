-- name: match
-- args: type, pattern
-- inputs: data
-- outputs: data
-- Modifies any arguments of the given data type that it receives.
-- Other types pass through unmodified.

local datatype, pattern = ...

if not pattern then pattern = datatype datatype = "*" end

local indexFilter

local dtpatterns = {
  table = "^table%[(%d*)%]$"
}

for dtype, dtpat in pairs(dtpatterns) do
  if datatype:match(dtpat) then
    local index = datatype:match(dtpat)
    if index then indexFilter = tonumber(index) end
    datatype = dtype
  end
end

local function checkActive()
  for _, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

while checkActive() do
  local inp = plumber.waitInput(1)
  while inp do
    if type(inp) == datatype or datatype == "*" then
      if indexFilter then
        inp[indexFilter] = inp[indexFilter]:match(pattern) or inp[indexFilter]
      else
        inp = inp:match(pattern) or inp
      end
    end
    plumber.write(inp)
    inp = plumber.pollInput(1)
  end
end
