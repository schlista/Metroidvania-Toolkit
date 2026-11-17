-- Engaged champions only. Reset runs from main's context: actor work is fields only.
local M = {}
local active = {}

function M.register(champion, actor) active[champion] = actor end
function M.unregister(champion) active[champion] = nil end

function M.reset_all(reason)
    local pending = {}
    for champion, actor in pairs(active) do pending[#pending+1] = {champion, actor} end
    for _, entry in ipairs(pending) do entry[1]:reset(entry[2], reason or "reset") end
end

return M
