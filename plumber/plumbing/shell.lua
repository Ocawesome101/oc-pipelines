local interactive = ...
if interactive == "interactive" then
  interactive = true
else
  interactive = false
end

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
  start|pipe|pipeline NAME
    Begin executing a pipeline.
  pw [s|r]
    Shut down or restart the computer.
  exit
    Exit an interactive shell.
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

local function processCommand(c)
  local words = split(c)
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
