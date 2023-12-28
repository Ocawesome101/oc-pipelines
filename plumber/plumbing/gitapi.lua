-- name: gitapi
-- args: mode
-- inputs: data
-- outputs: urls
-- Generate a request URL to the GitHub API

local request, parse = ...
local data = {}

if parse == "parse" then parse = true end
if request == "parse" then request = parse parse = true end

repeat
  local inputs = plumber.waitInputs()
  if inputs then
    for i=1, #inputs do
      data[#data+1] = plumber.pollInput(inputs[i])
    end
  end
until (not inputs)
    or (parse and data[#data][1] == "done")
    or (#inputs == 0 and not parse)

if #data == 0 then return end

local rqp = "([^%.]+)%.(.+)"
local rpp = "([^/]+/[^/]+)(/?[^/]*)"

if parse then
  local urqp = "https://api.github.com/([^/]+)/([^/]+/[^/]+)/(.+)"
  local header = data[1]
  local category, repo, name, branch = header[1]:match(urqp)

  if name:find('/') then
    name, branch = name:match("(.*)/([^/]+)")
  end

  local rdata = table.concat(data, "", 2, #data - 1)
  local json = plumber.loadLibrary("json")
  local result = json.decode(rdata)

  branch = branch:gsub("%?.*", "")

  if request == "urls" then
    if name == "git/trees" then
      for _, v in pairs(result.tree) do
        if v.type == "blob" then
          plumber.write(("https://raw.githubusercontent.com/%s/%s/%s")
            :format(repo, branch, v.path))
        end
      end
    else
      error("invalid parse request", 0)
    end
  elseif request == "commits" then
    if name == "branches" then
      for i=1, #data do
        plumber.write({name=data[i].name,commit=data[i].commit.sha})
      end
    else
      error("invalid parse request", 0)
    end
  end
else
  local category, name = request:match(rqp)
  name = name:gsub("%.", "/")

  for i=1, #data do
    local repo, branch = data[i]:match(rpp)
    if branch and #branch > 0 then branch = branch .. "?recursive=1" end
    if repo then
      plumber.write(
        string.format("https://api.github.com/%s/%s/%s%s",
          category, repo, name, branch) )
    end
  end
end
