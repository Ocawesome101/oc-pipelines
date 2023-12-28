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
    if #buf == 0 then return nil end
    return buf
  end

  function handle:write(d)
    return self.fs.write(self.fd, d)
  end

  function handle:seek(w, o)
    return self.fs.seek(self.fd, w, o)
  end

  function handle:close()
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

function plumber.getGraphicsOutput()
  return bootgpu
end

function plumber.setGraphicsOutput(gpu)
  if gpu.type == "gpu" then
    bootgpu = gpu
  elseif component.type(tostring(gpu)) == "gpu" then
    bootgpu = component.proxy(gpu)
  end
end

plumber.log = log
function plumber.setLogOutput(func)
  log = func
  plumber.log = func
end

local global_state = {}

local function readFile(f)
  local hand, err = fs.open(f)
  if not hand then return nil, err end
  local data = hand:read(math.huge)
  hand:close()
  return data
end

local pipelinesearch = "/plumber/pipelines/?.pipeline;/pipelines/?.pipeline"
local partsearch = "/plumber/plumbing/?.lua;/plumbing/?.lua"
local libsearch = "/plumber/libraries/?.lua;/libraries/?.lua"

function _G.loadfile(file, mode, env)
  local data, err = readFile(file)
  if not data then
    return nil, err
  end
  return load(data, "="..file, mode, env)
end

local libcache = {}

function plumber.loadLibrary(name)
  if libcache[name] then return libcache[name] end
  for dir in libsearch:gmatch("[^;]+") do
    local try = dir:gsub("%?", name)
    if fs.exists(try) then
      local func, err = loadfile(try)
      if not func then
        error(err, 0)
      end
      local lib = func()
      libcache[name] = lib
      return lib
    end
  end
  error("library " .. name .. " not found",0)
end

local function loadStage(name, args, input, output)
  local stage = {}
  for dir in partsearch:gmatch("[^;]+") do
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
        coro = coroutine.create(function()
          return func(table.unpack(args))
        end),
        name = name,
        inputs = input and {},
        outputs = output and {}
      }
    end
  end
  log("warning: pipeline stage '"..name.."' is not present")
  log("the pipeline may not function correctly")
end

local function loadWell(name, args)
  return loadStage(name, args, nil, true)
end

local function loadPipe(name, args)
  return loadStage(name, args, true, true)
end

local function loadFaucet(name, args)
  return loadStage(name, args, true)
end

-- multithreading-ish
local pipelines = {}

local function splitArguments(a, v)
  local r = {}
  for w in a:gmatch("[^,]+") do
    if v and w == "..." then
      for i=1, #v do
        r[#r+1] = v[i]
      end
    elseif v and w:match("v%[%d%]") then
      r[#r+1] = v[tonumber(w:match("v%[(%d)%]"))]
    else
      r[#r+1] = w
    end
  end
  return r
end

local function processAdditionalIO(addition, aux, pipe)
  if not addition then return end
  for io, name in addition:gmatch(" ?([a-z]+)(%b()) ?") do
    name=name:sub(2,-2)
    aux[name] = aux[name] or { type = name }
    if io == "input" then
      pipe.inputs[#pipe.inputs+1] = aux[name]
    elseif io == "output" then
      pipe.outputs[#pipe.outputs+1] = aux[name]
    end
  end
end

function plumber.loadPipeline(name, varargs)
  local new = {stages = {}, signals = {},
    name = name, id = math.random(100000,999999)}

  varargs = splitArguments(varargs or "")

  --local wells = {}
  --local pipes = {}
  --local faucets = {}
  local stages = {}
  local aux_pipes = {}

  local path
  for dir in pipelinesearch:gmatch("[^;]+") do
    local try = dir:gsub("%?", name)
    if fs.exists(try) then
      path = try
    end
  end
  if not path then
    return nil, "pipeline not found"
  end
  local data, err = readFile(path)
  if not data then return nil, err end

  for line in data:gmatch("[^\n]+") do
    local stage, thing, extra = line:match("([^:]*): ([a-zA-Z_]+)(.*)")
    local args, additional
    if stage ~= "#" then
      if extra:sub(1,1) == "(" then
        args, additional = extra:match("(%b()) ?(.*)")
      else
        args, additional = "()", extra
      end
      args = splitArguments(args:sub(2,-2), varargs)
      local directive = loadStage(thing, args, true, true)
    --[[
    if stage == "well" then
      directive = loadWell(thing, args)
      wells[#wells+1] = directive
    elseif stage == "pipe" then
      directive = loadPipe(thing, args)
      pipes[#pipes+1] = directive
    elseif stage == "faucet" then
      directive = loadFaucet(thing, args)
      faucets[#faucets+1] = directive
    elseif stage and stage ~= "#" then
      log("warning: malformed stage '"..stage.."' in pipeline "..name)
    end]]
      stages[#stages+1] = directive
      if directive then
        processAdditionalIO(additional, aux_pipes, directive)
      end
    end
  end

  --[[
  for i=1, #wells do
    wells[i].outputs[1] = {type = wells[i].name}
    new.stages[#new.stages+1] = wells[i]
  end

  for i=1, #pipes do
    pipes[i].outputs[1] = {type = pipes[i].name}
    new.stages[#new.stages+1] = pipes[i]
    if i == 1 then
      for w=1, #wells do
        pipes[i].inputs[w] = wells[w].outputs[1]
      end
    else
      pipes[i].inputs[1] = pipes[i-1].outputs[1]
    end
  end

  for i=1, #faucets do
    if pipes[#pipes] then
      faucets[i].inputs[1] = pipes[#pipes].outputs[1]
    elseif wells[#wells] then
      local final = faucets[i].inputs[#faucets[i].inputs]
      for w=1, #wells do
        faucets[i].inputs[w] = wells[w].outputs[1]
        faucets[i].inputs[w+1] = final
      end
    else
      log("warning: no valid inputs for faucet: " .. faucets[i].name)
    end
    new.stages[#new.stages+1] = faucets[i]
  end]]

  for i=1, #stages do
    new.stages[i] = stages[i]
  end

  return new
end

function plumber.startPipeline(name, args)
  local pl, err = plumber.loadPipeline(name, args)
  if not pl then
    log("pipeline loading failed: " .. err)
    return false
  end
  pipelines[#pipelines+1] = pl
  return pl.id
end

local _currentPipeline, _currentPipelineStage

function plumber.tickPipeline(line)
  _currentPipeline = line
  local lineTimeout = math.huge
  for i=1, #line.stages do
    if line.stages[i] then
      _currentPipelineStage = line.stages[i]
      local ok, reason = coroutine.resume(line.stages[i].coro)
      if not ok then
        local inp = _currentPipelineStage.inputs
        local oup = _currentPipelineStage.outputs

        if inp then
          for i=1, #inp do
            inp[i].inactive = true
          end
        end
        if oup then
          for i=1, #oup do
            oup[i].inactive = true
          end
        end

        if reason ~= "cannot resume dead coroutine" then
          log("warning: pipeline stage '"..line.stages[i].name.."' ("..i..") exited uncleanly")
          log(tostring(reason))
          line.unclean = true
        end
        table.remove(line.stages, i)
      elseif type(reason) == "number" then
        lineTimeout = math.max(0, math.min(lineTimeout, reason))
      end
    end
  end
  if #line.stages == 0 then
    line.complete = true
  end
  return lineTimeout
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

function plumber.getRunningPipelines()
  local ret = {}
  for i=1, #pipelines do
    ret[#ret+1] = {id = pipelines[i].id, name = pipelines[i].name}
  end
  return ret
end

function plumber.waitForPipeline(id)
  local run = true
  while run do
    run = false
    for i=1, #pipelines do
      if pipelines[i].id == id then
        run = true
      end
    end
    coroutine.yield(0)
  end
  return true
end

-- retrieve a list of output IDs and their type
function plumber.getOutputs()
  local outputs = _currentPipelineStage.outputs
  if not outputs then return nil end
  local ret = {}
  for i=1, #outputs do
    ret[i] = {id = i, type = outputs[i].type, active = not outputs[i].inactive}
  end
  return ret
end

-- TODO: input timeouts
-- TODO: output buffer size limits

-- returns one item from that specific input, if present
-- otherwise returns nil
function plumber.pollInput(id)
  local inputs = _currentPipelineStage.inputs
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  if not inputs[id] then
    return nil, "invalid pipeline stage input ID: " .. id
  end
  if #inputs[id] > 0 then
    return table.remove(inputs[id], 1)
  end
end

-- returns a table containing the IDs of inputs that have data available
-- for reading
-- these must then individually be read with pollInput() or waitInput()
-- returns nil when there are no active inputs left
function plumber.pollInputs()
  local inputs = _currentPipelineStage.inputs
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  local ret = {}
  local active = false
  for i=1, #inputs do
    if #inputs[i] > 0 then
      ret[#ret+1] = i
    end
    if not inputs[i].inactive then active = true end
  end
  if not active then return nil end
  return ret
end

-- wait until an input value is available from a given ID
-- returns the same as pollInput()
-- returns nil if the input is no longer active
function plumber.waitInput(id, timeout)
  local inputs = _currentPipelineStage.inputs
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  if not inputs[id] then
    return nil, "invalid pipeline stage input ID: " .. id
  end

  timeout = timeout or math.huge
  local time = computer.uptime() + timeout

  while #inputs[id] == 0 and not inputs[id].inactive do
    coroutine.yield(timeout)
    if time - computer.uptime() <= 0 then break end
  end

  if inputs[id].inactive then coroutine.yield(0) end

  return table.remove(inputs[id], 1)
end

-- wait until an input value is available from at least one input
-- returns the same as pollInputs()
-- returns nil when there are no active inputs left
function plumber.waitInputs(timeout)
  local inputs = _currentPipelineStage.inputs
  if not inputs then
    return nil, "pipeline well has no inputs"
  end
  local ret = {}

  timeout = timeout or math.huge
  local time = computer.uptime() + timeout
  local yielded = false

  while true do
    local active = false

    for i=1, #inputs do
      active = active or not inputs[i].inactive
      if #inputs[i] > 0 then
        ret[#ret+1] = i
      end
    end

    if #ret > 0 then break end
    if not active then 
      if not yielded then coroutine.yield(0) end
      return nil
    end

    yielded = true
    coroutine.yield(timeout)
    if time - computer.uptime() <= 0 then break end
  end

  return ret
end

-- similar to the above, but for OpenComputers signals
function plumber.pollSignal()
  local signals = _currentPipeline.signals
  if #signals > 0 then
    return table.unpack(table.remove(signals, 1))
  end
end

-- XXX unlike the other wait() functions, this one returns a value
function plumber.waitSignal()
  local signals = _currentPipeline.signals
  while #signals == 0 do
    coroutine.yield()
  end
  return table.unpack(table.remove(signals, 1))
end

-- write one or more values to a single output
function plumber.writeSingle(id, ...)
  local outputs = _currentPipelineStage.outputs 
  if not outputs then
    return nil, "pipeline well has no outputs"
  end
  if not outputs[id] then
    return nil, "bad pipeline stage output ID: " .. id
  end

  local args = table.pack(...)
  for i=1, args.n do
    outputs[id][#outputs[id]+1] = args[i]
  end

  return true
end

-- write one or more values to every output
function plumber.write(...)
  local outputs = _currentPipelineStage.outputs 
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

function plumber.readGlobalState(k)
  return global_state[k]
end

function plumber.writeGlobalState(k, v)
  global_state[k] = v
  return global_state[k]
end


function plumber.completeCurrentPipeline()
  _currentPipeline.complete = true
end


computer.pushSignal("startup")
plumber.startPipeline("shell")

local done = false
local nextYieldTimeout = math.huge
while true do
  local signal = table.pack(computer.pullSignal(nextYieldTimeout))
  nextYieldTimeout = math.huge
  local ioffset = 0
  for i=1, #pipelines do
    if pipelines[i] then
      if signal.n > 0 then
        pipelines[i].signals[#pipelines[i].signals+1] = signal
        if #pipelines[i].signals > 256 then
          table.remove(pipelines[i].signals, 1)
        end
      end
      local timeout = plumber.tickPipeline(pipelines[i])
      nextYieldTimeout = math.min(timeout, nextYieldTimeout)
      if pipelines[i].complete then
        --log("pipeline completed: " .. pipelines[i].name)
        table.remove(pipelines, i)
      end
    end
  end
  if #pipelines == 0 and not done then
    done = true
    computer.beep(880)
    computer.beep(440)
    computer.beep(220)
    log("All pipelines completed!")
  end
end
