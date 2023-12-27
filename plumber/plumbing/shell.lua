-- name: shell
-- args: interactive
-- inputs: 1
-- outputs: any

local interactive = (...) == "interactive"

local prompt = "Y> "

local function split(c)
  local words = {}
  for word in c:gmatch("[^ ]+") do
    words[#words+1] = word
  end
  return words
end

local commands = {}

function commands.help()
  plumber.write([=[
shell: Wrench (c) 2023 Ocawesome101
Basic command syntax:
  verb [arguments [...]]

Commands:
  start|pipe|pipeline [wait] NAME
    Begin executing a pipeline.
    If [wait], wait for completion.
  pw [s|r]
    Shut down or restart the computer.
  stat
    Print some info.
  exit
    Exit an interactive shell.

Unknown commands default to 'pipe wait COMMAND'.
]=])
end

function commands.pipeline(waitOrName, nameOrArgs, args)
  local wait = false
  local name
  if waitOrName == "wait" or waitOrName == "-" then
    wait = waitOrName == "wait"
    name = nameOrArgs
    
  else
    name = waitOrName
    args = nameOrArgs
  end

  local id, err = plumber.startPipeline(name, args)
  if not id then return end
  if wait then
    plumber.waitForPipeline(id)
    -- flush readkey queue
    repeat until not plumber.pollInput(1)
  elseif interactive then
    plumber.write("started as id: " .. id)
  end
end

commands.start, commands.pipe = commands.pipeline, commands.pipeline

function commands.pw(a)
  if a == "s" or not a then
    computer.shutdown()
  elseif a == "r" then
    computer.shutdown(true)
  else
    plumber.write("bad argument (need s or r)\n")
  end
end

local shouldExit = false
function commands.exit()
  shouldExit = true
end

function commands.stat()
  local total = computer.totalMemory()
  local free = computer.freeMemory()
  local used = total - free
  plumber.write("Memory use: " .. (used//1024).."/"..(total//1024).."KB\n")
  plumber.write("Uptime: " .. computer.uptime() .. "\n")
end

local function processCommand(c)
  local words = split(c)
  if not commands[words[1]] then
    words = split("pipe wait " .. c)
  end
  if commands[words[1]] then
    commands[words[1]](table.unpack(words, 2))
  elseif interactive then
    plumber.write("command not found\n")
  end
end

if interactive then
  plumber.write(prompt)
end
while not shouldExit do
  local input = plumber.waitInput(1)
  processCommand(input)
  if interactive then plumber.write(prompt) end
end

plumber.completeCurrentPipeline()
