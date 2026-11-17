-- Optional platform boundary. Without an adapter every operation is a pure no-op.
-- Adapters use dot-call functions with these same signatures; no engine dependency.
local M = {}
local adapter
function M.set_adapter(value) adapter=type(value)=="table" and value or nil end
function M.init() if adapter and adapter.init then return adapter.init() end end
function M.update(dt) if adapter and adapter.update then return adapter.update(dt) end end
function M.final() if adapter and adapter.final then return adapter.final() end end
function M.unlock_achievement(id)
    if adapter and adapter.unlock_achievement then return adapter.unlock_achievement(id) end
end
function M.sync_achievements(ids)
    if adapter and adapter.sync_achievements then return adapter.sync_achievements(ids) end
end
function M.set_rich_presence(state, region_id)
    if adapter and adapter.set_rich_presence then return adapter.set_rich_presence(state, region_id) end
end
return M
