-- Shared live encounter state for authored arena pieces.
local M = {}

local function named(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

--- Return boss phase, encounter activity, lock state and source reason.
-- Requires stay lazy so arena and boss services can also use this resolver.
function M.resolve(criteria)
    criteria = criteria or {}
    local Arena = require "mvtk.bosses.boss_arena"
    local Bosses = require "mvtk.bosses.boss_manager"
    local arena_id = criteria.arena_id
    local arena
    if arena_id and arena_id ~= "" then
        arena = Arena.get_arena(arena_id)
    else
        arena = Arena.get_active_arena()
        arena_id = arena and arena.id
    end
    local locked = arena and arena.locked == true or false
    if arena_id and not named(criteria.boss_id) and not named(criteria.boss_type) and Bosses.arena_live_phase then
        local phase, live, group_locked = Bosses.arena_live_phase(arena_id)
        if live then return phase, true, locked or group_locked, "boss" end
    end
    local boss_id = Bosses.find_boss_id({arena_id = arena_id,
        boss_id = criteria.boss_id, boss_type = criteria.boss_type})
    local boss = boss_id and Bosses.get_boss(boss_id)
    if boss and not boss.defeated then
        local configured_arena = boss.config and boss.config.arena
        locked = locked or (configured_arena ~= nil and configured_arena ~= false and configured_arena ~= "")
        return Bosses.get_boss_phase(boss_id), true, locked, "boss"
    end
    -- A piece that names its boss follows only that boss. After a defeat the
    -- arena stays locked through the cleanup delay, but the encounter is over.
    if named(criteria.boss_id) or named(criteria.boss_type) then
        return 0, false, locked, "no_live_boss"
    end
    if arena then
        local phase = arena.phase or arena.current_phase or 0
        if locked and phase == 0 then phase = 1 end
        return phase, locked or arena.boss_active == true, locked, "arena"
    end
    return 0, false, false, "none"
end

return M
