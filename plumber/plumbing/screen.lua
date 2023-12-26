-- cannot run as a well
if not plumber.getInputs() then
  return
end

local cx, cy = 1, 2
local w, h

local function readcpos()
  cx = plumber.readGlobalState("cursor_X") or cx
  cy = plumber.readGlobalState("cursor_Y") or cy
  if cx == 0 then cy = cy - 1 cx = w-1 end
  if cy >= h then cy = h end
end

local function writecpos(x, y)
  cx, cy = x or cx, y or cy
  plumber.writeGlobalState("cursor_X", cx)
  plumber.writeGlobalState("cursor_Y", cy)
end

local gpu = plumber.getGraphicsOutput()
if type(gpu) == "string" or not gpu then return end

local on = false
local function setcblink(yes)
  on = not not plumber.readGlobalState("cursor_B")
  if cx < 1 or cy < 1 or cx > w or cy > h then
    return
  end
  local of, ob = gpu.getForeground(), gpu.getBackground()
  if (yes and not on) or (on and not yes) then
    on = not on
    local c, f, b = gpu.get(cx, cy)
    gpu.setForeground(b)
    gpu.setBackground(f)
    gpu.set(cx, cy, c)
    gpu.setForeground(of)
    gpu.setBackground(ob)
  end
  plumber.writeGlobalState("cursor_B", on)
end

w, h = gpu.getResolution()

local function writeText(t)
  setcblink(false)
  readcpos()
  while #t > 0 do
    local brk = math.min(t:find("\n") or math.huge, w-cx)
    local chunk = t:sub(1, brk)
    t = t:sub(#chunk+1)
    gpu.set(cx, cy, (chunk:gsub("\n","")))
    cx = cx + #chunk
    if cx >= w or chunk:sub(-1) == "\n" then
      cx = 1
      cy = cy + 1
    end
    if cy > h then
      cy = cy - 1
      gpu.copy(1, 1, w, h, 0, -1)
      gpu.fill(1, h, w, 1, " ")
    end
  end
  writecpos()
  setcblink(true)
end

if (...) ~= "nolog" then
  plumber.setLogOutput(function(text)
    writeText(text.."\n")
  end)
end

readcpos()
while true do
  local inputs = plumber.waitInputs(1)
  if not inputs then -- no longer active!
    break
  end
  for i=1, #inputs do
    local value = tostring(plumber.pollInput(inputs[i]))
    writeText(value)
  end
end
