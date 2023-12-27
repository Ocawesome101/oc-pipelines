-- name: readline
-- args: none
-- inputs: none
-- outputs: any, :screen

-- find screen output, if there is one
local outputs = plumber.getOutputs()

local screenOutput

for i=1, #outputs do
  if outputs[i].type == "screen" then
    screenOutput = outputs[i].id
  end
end

local line = ""

local function checkActive()
  for i, output in pairs(plumber.getOutputs()) do
    if output.active then return true end
  end
end

local KEY_LEFT = 203
local KEY_RIGHT = 205
local KEY_BACKSPACE = 8
local KEY_ENTER = 13

local function setc(x, y)
  plumber.writeGlobalState("cursor_X", x)
  plumber.writeGlobalState("cursor_Y", y)
end

local function getc()
  return plumber.readGlobalState("cursor_X"),
    plumber.readGlobalState("cursor_Y")
end

local function movec(xd)
  local cx, cy = getc()
  cx = cx - 1
  setc(cx, cy)
end

-- ensure only one readline does things with the screen
local rlc = plumber.readGlobalState("readlineCount") or 0
plumber.writeGlobalState("readlineCount", rlc + 1)

while checkActive() do
  local signal = table.pack(plumber.waitSignal())
  if signal[1] == "key_down" then
    if signal[3] > 31 and signal[3] < 127 then
      line = line .. string.char(signal[3])
      if rlc == 0 then
        plumber.writeSingle(screenOutput, string.char(signal[3]))
      end
    elseif signal[3] == KEY_ENTER then
      if rlc == 0 then plumber.writeSingle(screenOutput, "\n") end
      coroutine.yield(0) -- io sync
      for i=1, #outputs do
        if i ~= screenOutput then
          plumber.writeSingle(i, line)
        end
      end
      line = ""
    elseif signal[3] == KEY_BACKSPACE and #line > 0 then
      line = line:sub(1, -2)
      if rlc == 0 then
        movec(-1)
        plumber.writeSingle(screenOutput, " ")
        coroutine.yield(0) -- io sync
        movec(-1)
        plumber.writeSingle(screenOutput, "")
      end
    end
  end
end

plumber.writeGlobalState("readlineCount",
  plumber.readGlobalState("readlineCount") - 1)
