-- name: file 
-- inputs: none
-- outputs: 1
--  1: data

local file, chunkSize = ...
if not file then error("no file provided") end

chunkSize = tonumber(chunkSize) or math.huge

local handle = fs.open(file)
repeat
  local chunk = handle:read(chunkSize)
  if chunk then plumber.write(chunk) end
until not chunk

handle:close()
