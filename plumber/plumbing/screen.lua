-- cannot run as a well
if not plumber.getInputs() then
  return
end

local cx, cy = 1, 2

local function readcpos()
  cx = plumber.readGlobalState("cursor_X") or cx
  cy = plumber.readGlobalState("cursor_Y") or cy
  if cx == 0 then cy = cy - 1 cx = w end
end

local function writecpos(x, y)
  cx, cy = x or cx, y or cy
  plumber.writeGlobalState("cursor_X", cx)
  plumber.writeGlobalState("cursor_Y", cy)
end

local gpu = plumber.getGraphicsOutput()
if type(gpu) == "string" or not gpu then return end

local w, h = gpu.getResolution()

local function writeText(t)
  readcpos()
  while #t > 0 do
    local brk = math.min(t:find("\n") or math.huge, cx)
    local chunk = t:sub(1, brk)
    t = t:sub(#chunk+1)
    gpu.set(cx, cy, (chunk:gsub("\n","")))
    cx = cx + #chunk
    if cx >= w or chunk:sub(-1) == "\n" then
      cx = 1
      cy = cy + 1
    end
    if cy > h then
      gpu.copy(1, 1, w, h, 0, -1)
      gpu.fill(1, h, w, 1, " ")
    end
  end
  writecpos()
end

readcpos()
while true do
  local inputs = plumber.waitInputs()
  if not inputs then -- no longer active!
    break
  end
  for i=1, #inputs do
    local value = tostring(plumber.pollInput(inputs[i]))
    writeText(value)
  end
end
