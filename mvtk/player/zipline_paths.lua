-- Source-owned world paths. Large arrays travel by key to stay under msg's 2 KB limit.
-- A streamed Zip Line unregisters on final; an accepted ride copies its segments.
local M = {}
local paths = {}
function M.set(key, points) paths[key]=points end
function M.get(key) return paths[key] end
function M.remove(key) paths[key]=nil end
return M
