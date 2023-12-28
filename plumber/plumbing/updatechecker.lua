-- name: updatechecker
-- args: none
-- inputs: data
-- outputs: data
-- Check for updates based on git commit

local base = (...) or "/plumber"

local updateConfig = {}
local handle, err = fs.open((base or "/plumber").."/update.cfg")
if not handle then
  error("no update configuration defined - /plumber/update.cfg", 0)
end
local data = handle:read(math.huge) or ""
handle:close()

for line in data:gmatch("[^\n]+") do
  local name, value = line:match("([^ ]+) (.+)")
  if name and value then updateConfig[name] = value end
end

updateConfig.repo = updateConfig.repo or "ocawesome101/oc-pipelines"
updateConfig.branch = updateConfig.branch or "foremost"
updateConfig.commit = updateConfig.commit or "no"

local function checkActive()
  for _, input in pairs(plumber.getInputs()) do
    if input.active then return true end
  end
end

local jsonData = ""
while checkActive() do
  local input = plumber.waitInput(1)
  if type(input) == "string" then
    jsonData = jsonData .. input
  end
end

if #jsonData == 0 then return end

local json = plumber.loadLibrary("json")

local data = json.decode(jsonData)
local carry_on
for i=1, #data do
  if data[i].name == updateConfig.branch then
    if data[i].commit.sha:sub(1, #updateConfig.commit)~=updateConfig.commit then
      carry_on = {name = data[i].name, commit = data[i].commit.sha}
    end
  end
end

if not carry_on then return end

plumber.write(updateConfig.repo.."/"..updateConfig.branch)
