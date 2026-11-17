-- Large source text stays in shared Lua state rather than a message payload.
local M, entries, serial = {}, {}, 0
function M.stage(entry)
  serial = serial + 1
  entries[serial] = entry
  return serial
end
function M.take(token)
  local entry = entries[token]
  if token then entries[token] = nil end
  return entry
end
return M
