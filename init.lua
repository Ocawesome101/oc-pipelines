local addr
if computer.getBootAddress then
  addr = computer.getBootAddress()
else
  for a in component.list("filesystem") do
    if component.exists(a, "/plumber/core.lua") then
      addr = a
      break
    end
  end
end

if not addr then
  error("no Plumber instance found - cannot continue")
end

local h = component.invoke(addr, "open", "/plumber/core.lua", "r")
if not h then
  error("failed opening Plumber core")
end

local data = ""
repeat
  local chunk = component.invoke(addr, "read", h, math.huge)
  data = data .. (chunk or "")
until not chunk

component.invoke(addr, "close", h)

assert(assert(load(data, "=plumber/core", "t", _G))(addr))
