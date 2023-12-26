-- name: dir
-- args: path
-- inputs: none
-- outputs: 1
--  1: data

local dir = ...
if not dir then error("dir: no path provided", 0) end

local entries = fs.list(dir)
if not entries then error("dir: nonexistent", 0) end

table.sort(entries)

for i=1, #entries do
  plumber.write(entries[i])
end
