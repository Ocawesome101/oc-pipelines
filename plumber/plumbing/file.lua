-- name: file
-- args: path, chunkSize, optional
-- inputs: none
-- outputs: 1
--  1: data

local file, chunkSize, optional = ...
if file == "optional" then optional = file file = nil end
local optional = chunkSize == "optional" or optional == "optional"
if not file and not optional then error("file: no file provided", 0) end
if not file then plumber.write("") return end

chunkSize = tonumber(chunkSize) or math.huge

local handle = fs.open(file)
if not handle then
  if not optional then error("file: file not found", 0) end
  return
end

repeat
  local chunk = handle:read(chunkSize)
  if chunk then plumber.write(chunk) end
until not chunk

handle:close()
