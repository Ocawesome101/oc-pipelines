-- name: edit
-- args: interactive
-- inputs: data, control
-- outputs: data, :screen?

--[[
A streaming editor, similar to sed.

General command format:
  L,LcA
  L is line spec:
    N for specified line
    '.' for current line
    '$' for end of file
    '+-'N for + or - N lines from current
  if c is a number, sets the current line

valid commands:
  d       delete line(s)
  i       insert text until receiving a line with solely '.'
  n       disable printing line numbers (default when non-interactive)
  N       enable printing line numbers (default when interactive)
  P       paste last deleted line(s)
  p       print the given range of lines, or the current line
  q       quit editor
  s/a/b   replace a with b using lua patterns
  wFILE  write buffer to FILE, or to output if FIlE not given
]]

local interactive = (...) == "interactive"

local running = true
local function checkActive()
  if not running then return false end
  for i, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

local screenOutput
for i, output in pairs(plumber.getOutputs()) do
  if output.type:match("screen") then
    screenOutput = i
  end
end

-- editing buffer
local buffer = {""}
local cut_buffer
local current = 1
local insert = false
local lineno = interactive

local commands = {}
function commands.d(s,e)
  s = s or current
  e = e or current
  local n = e - s + 1
  cut_buffer = {}
  for i=1, n do
    cut_buffer[i] = table.remove(buffer, s)
  end
end

function commands.i()
  insert = true
end

function commands.n()
  lineno = false
end

function commands.N()
  lineno = true
end

function commands.P(L)
  for i=1, #cut_buffer do
    table.insert(buffer, L+i, cut_buffer[i])
  end
end

function commands.p(s, e)
  for i=s, e do
    plumber.write(
      ((lineno and string.format("%4d ", math.floor(i))) or "") ..
      buffer[i] .. "\n")
  end
end

function commands.q()
  running = false
  if interactive then
    plumber.completeCurrentPipeline()
  end
end

function commands.s(s, e, pat)
  local find, replace = pat:match("/(.*[^\\])/(.+)")
  for i=s, e do
    buffer[i] = buffer[i]:gsub(find, replace)
  end
end

function commands.w(s, e, file)
  if file then
    local hand, err = fs.open(file, "w")
    if not hand then
      error(err, 0)
    end
    for i=1, #buffer do
      hand:write(buffer[i].."\n")
    end
    hand:close()
  else
    for i=1, #buffer do
      for o, output in pairs(plumber.getOutputs()) do
        if output.type == "screen" then
          plumber.writeSingle(o, buffer[i] .. "\n")
        else
          plumber.writeSingle(o, buffer[i])
        end
      end
    end
  end
end

local npat = { "([%+%-]?%d+)", "([%+%-]?%d+),([%+%-]?%d+)" }
local function processCommand(cmd)
  if tonumber(cmd) then
    current = tonumber(cmd)
    return
  end

  local st, en = current, current
  local lsp, c, a = cmd:match("([^a-z]*)([a-z]?)(.*)")
  if lsp:find(",") then
    st, en = lsp:match("(.*),(.*)")
    if #st == 0 then st = current end
    if #en == 0 then en = current end
  elseif #lsp > 0 then
    st = lsp
  end

  if #lsp == 0 and #c == 0 and #a == 0 then
    if screenOutput then
      plumber.writeSingle(screenOutput, "?\n")
    end
    return
  end

  if type(st) == "string" and st:sub(1,1):match("[%+%-]") then
    st = current + tonumber(st) end
  if type(en) == "string" and en:sub(1,1):match("[%+%-]") then
    en = current + tonumber(en) end

  if st == "$" then st = #buffer end
  if en == "$" then en = #buffer end
  if st == "%" then st, en = 1, #buffer end

  st, en = tonumber(st) or current, tonumber(en) or current
  if st < 1 then st = current + st end
  if en < 1 then en = current + en end

  st, en = math.min(st, en), math.max(st, en)
  st, en = math.max(1, st), math.min(math.max(1, #buffer), en)

  if commands[c] then
    if #a == 0 then a = "" end
    commands[c](st, en, a)
  elseif screenOutput then
    plumber.writeSingle(screenOutput, "?\n")
  end
end

local control, data
for i, input in pairs(plumber.getInputs()) do
  if input.type:match("control") then
    control = i
  elseif input.type:match("data") then
    data = i
  end
end

while checkActive() do
  if data then
    local line = plumber.pollInput(data)
    while line do
      if #buffer[1] == 0 then buffer[1] = nil end
      buffer[#buffer+1] = line:gsub("[\r\n]", "")
      line = plumber.pollInput(data)
    end
  end

  if insert then
    local line = plumber.pollInput(control)
    while line do
      if line == "." then
        insert = false
      else
        table.insert(buffer, current, tostring(line))
        current = math.max(#buffer+1, current + 1)
      end
      line = plumber.pollInput(control)
    end
  else
    local command = plumber.pollInput(control)
    while command do
      processCommand(tostring(command))
      command = plumber.pollInput(control)
    end
  end
  coroutine.yield()
end
