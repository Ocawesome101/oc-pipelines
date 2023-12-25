-- Plumber: the core of Pipelines

local bootfs = component.proxy((...))

local function log() end

local bootgpu = component.list("gpu", true)()

if bootgpu then
  local screen = component.list("screen", true)()
  if screen then
    bootgpu = component.proxy(bootgpu)
    local y = 0
    log = function(msg)
      for line in msg:gmatch("[^\n]+") do
        y = y + 1
        bootgpu.set(1, y, line)
      end
    end
  end
end

log("🔧Plumber (c) 2023 Ocawesome101")
computer.beep(440)

-- filesystem interactions
_G.fs = {}
do
  local mounts = {["/"] = bootfs}

  local function split(path)
    local segments = {}
    for piece in path:gmatch("[^/\\]+") do
      if piece == ".." then
        segments[#segments] = nil

      elseif piece ~= "." then
        segments[#segments+1] = piece
      end
    end

    return segments
  end

  local function resolve(path)
    local mnt, rem = "/", path
    for m in pairs(mounts) do
      if path:sub(1, #m) == m and #m > #mnt then
        mnt, rem = m, path:sub(#m+1)
      end
    end

    if #rem == 0 then rem = "/" end

    --printk(k.L_DEBUG, "path_to_node(%s) = %s, %s",
    --  path, tostring(mnt), tostring(rem))

    return mounts[mnt], rem or "/"
  end

  local handle = {}

  function handle:read(q)
    local buf = ""
    repeat
      local chunk = self.fs.read(self.fd, q - #buf)
      buf = buf .. (chunk or "")
    until #buf == q or not chunk
    return buf
  end

  function handle:write(d)
    return self.fs.write(self.fd, d)
  end

  function handle:seek(w, o)
    return self.fs.seek(self.fd, w, o)
  end

  function handle.close()
    return self.fs.close(self.fd)
  end

  function fs.open(file, mode)
    mode = mode or "r"
    local mount, rem = resolve(file)
    if mode == "r" and not mount.exists(rem) then
      return nil, "file does not exist"
    end
    
    local fd = mount.open(rem)

    return setmetatable({fs=mount,fd=fd}, {__index = handle})
  end

  setmetatable(fs, {__index = function(self, k)
    self[k] = function(path)
      local mount, rem = resolve(path)
      return mount[k](rem)
    end
    return self[k]
  end})
end

-- global 'plumber' api
_G.plumber = {}

local global_states = {}

local function readFile(f)
  local hand, err = fs.open(f)
  if not hand then return nil, err end
  local data = hand:read(math.huge)
  hand:close()
  return data
end

local search = "/plumber/plumbing/?.lua"

function _G.loadfile(file, mode, env)
  local data, err = readFile(file)
  if not data then
    return nil, err
  end
  return load(data, "="..file, mode, env)
end

local function loadStage(name, input, output)
  local stage = {}
  for dir in search:gmatch("[^;]+") do
    local try = dir:gsub("%?", name)
    if fs.exists(try) then
      local func, err = loadfile(try)
      if not func then
        log("warning: pipeline loading failed for stage '"..name.."'")
        log("the pipeline may not function correctly")
        log(err)
        return nil
      end
      return {
        coro = coroutine.create(func),
        name = name,
        inputBuffer = input and {},
        outputBuffer = output and {}
      }
    end
  end
  log("warning: pipeline stage '"..name.."' is not present")
  log("the pipeline may not function correctly")
end

local function loadWell(name)
  return loadStage(name, false, true)
end

local function loadPipe(name)
  return loadStage(name, true, true)
end

local function loadFaucet(name)
  return loadStage(name, true, false)
end

-- multithreading-ish
local pipelines = {}
function plumber.startPipeline(name)
  local new = {stages = {}, signals = {}}

  local wells = {}
  local pipes = {}
  local faucets = {}

  local data = readFile("/plumber/pipelines/"..name..".pipeline")

  for line in data:gmatch("[^\n]+") do
    local stage, thing = line:match("([^:]+): (.+)")
    if stage == "well" then
      new.wells[#new.wells+1] = loadWell(thing)
    elseif stage == "pipe" then
      new.pipes[#new.pipes+1] = loadPipe(thing)
    elseif stage == "faucet" then
      new.faucets[#new.faucets+1] = loadFaucet(thing)
    elseif stage ~= "#" then
      log("warning: malformed stage '"..stage.."' in pipeline "..name)
    end
  end

  -- hopefully this system should allow more complex pipelines in the future
  -- once i have a better system for defining them
  for i=1, #wells do
    wells[i].outputBuffer[1] = {type = wells[i].name}
    new.stages[#new.stages+1] = wells[i]
  end

  for i=1, #pipes do
    pipes[i].outputBuffer[1] = {type = pipes[i].name}
    new.stages[#new.stages+1] = pipes[i]
    if i == 1 then
      for i=1, #wells do
        pipes[i].inputBuffer[i] = wells[i].outputBuffer[1]
      end
    else
      pipes[i].inputBuffer[1] = pipes[i-1].outputBuffer[1]
    end
  end

  for i=1, #faucets do
    faucets[i].inputBuffer[1] = pipes[#pipes].outputBuffer[1]
    new.stages[#new.stages+1] = faucets[i]
  end

  return new
end

local _currentPipelineStage

function plumber.tickPipeline(line)
  for i=1, #line.stages do
    _currentPipelineStage = line.stages[i]
    local ok, reason = coroutine.resume(line.stages[i].coro)
    if not ok then
      local inp = _currentPipelineStage.inputs
      local oup = _currentPipelineStage.outputs

      for i=1, #inp do
        inp[i].inactive = true
      end
      for i=1, #oup do
        oup[i].inactive = true
      end

      table.remove(line.stages, i)
      if reason ~= "cannot resume dead coroutine" then
        log("warning: pipeline stage '"..line.wells[i].name.."' exited uncleanly")
        line.unclean = true
    end
  end
  if #line.stages == 0 then
    line.complete = true
  end
end

-- retrieve a list of input IDs and their type
function plumber.getInputs()
  local inputs = _currentPipelineStage.inputs
  if not inputs then return nil end
  local ret = {}
  for i=1, #inputs do
    ret[i] = {id = i, type = inputs[i].type, active = not inputs[i].inactive}
  end
  return ret
end

-- retrieve a list of output IDs and their type
function plumber.getOutputs()
  local outputs = _currentPipelineStage.outputs
  if not outputs then return nil end
  local ret = {}
  for i=1, #outputs do
    ret[i] = {id = i, type = outputs[i].type, active = not inputs[i].inactive}
  end
  return ret
end

-- TODO: input timeouts
-- TODO: output buffer size limits

-- returns one item from that specific input, if present
-- otherwise returns nil
function plumber.pollInput(id)
  local inputs = _currentPipelineStage.inputBuffer
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  if not inputs[id] then
    return nil, "invalid pipeline stage input ID: " .. id)
  end
  if #inputs[id] > 0 then
    return table.remove(inputs[id], 1)
  end
end

-- returns a table containing the IDs of inputs that have data available
-- for reading
-- these must then individually be read with pollInput() or waitInput()
function plumber.pollInputs()
  local inputs = _currentPipelineStage.inputBuffer
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  local ret = {}
  for i=1, #inputs do
    if #inputs[i] > 0 then
      ret[#ret+1] = i
    end
  end
  return ret
end

-- wait until an input value is available from a given ID
-- returns the same as pollInput()
function plumber.waitInput(id)
  local inputs = _currentPipelineStage.inputBuffer
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  if not inputs[id] then
    return nil, "invalid pipeline stage input ID: " .. id)
  end
  while #inputs[id] == 0 do
    coroutine.yield()
  end
end

-- wait until an input value is available from at least one input
-- returns the same as pollInputs()
function plumber.waitInputs()
  local inputs = _currentPipelineStage.inputBuffer
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  local ret = {}
  while true do
    for i=1, #inputs do
      if #inputs[i] > 0 then
        ret[#ret+1] = i
      end
    end
    if #ret > 0 then break end
    coroutine.yield()
  end
  return ret
end

-- similar to the above, but for OpenComputers signals
function plumber.pollSignal()
  local signals = _currentPipelineStage.signals
  if #signals > 0 then
    return table.remove(signals[1])
  end
end

-- XXX unlike the other wait() functions, this one returns a value
function plumber.waitSignal()
  local signals = _currentPipelineStage.signals
  while #signals == 0 do
    coroutine.yield()
  end
  return table.remove(signals[1])
end

-- write one or more values to a single output
function plumber.writeSingle(id, ...)
  local outputs = _currentPipelineStage.outputBuffer 
  if not outputs then
    return nil, "pipeline well has no outputs"
  end
  if not outputs[id] then
    return nil, "bad pipeline stage output ID: " .. id)
  end

  local args = table.pack(...)
  for i=1, args.n do
    outputs[id][#outputs[id]+1] = args[i]
  end

  return true
end

-- write one or more values to every output
function plumber.write(...)
  local outputs = _currentPipelineStage.outputBuffer 
  if not outputs then
    return nil, "pipeline well has no outputs"
  end

  local args = table.pack(...)

  for i=1, args.n do
    for id=1, #outputs do
      outputs[id][#outputs[id]+1] = args[i]
    end
  end

  return true
end

while true do
  computer.pullSignal()
  for i=1, #pipelines do
  end
end
