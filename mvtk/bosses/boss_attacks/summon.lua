--- Boss summon attack executor.
-- Creates room-owned enemies in a ring around the boss.
-- @module boss_attacks.summon

local C = require "mvtk.bosses.boss_attacks.common"
local Spawn = require "mvtk.enemies.enemy_spawn_service"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    local summon = pattern.summon or {}
    local defaults = require("developer.config.runtime_settings").section("enemy_defaults", require "developer.config.enemy_defaults")
    local owner = "boss:" .. boss.boss_id
    local pos = go.get_world_position()
    local Rooms = require "mvtk.map.streaming.room_manager"
    local Geometry = require "mvtk.map.streaming.room_geometry"
    -- Baked bosses have no config.room_id. Resolve once at the boss, because
    -- a ring position may already be across a room boundary.
    local room = Geometry.normalize_room_id(Rooms.get_room_for_position(pos))
        or Geometry.normalize_room_id(Rooms.get_current_room())
    if not room then return end
    local cap = summon.max_active or C.Defaults.summon_max_active
    local drops = summon.drops
    if drops == nil then drops = C.Defaults.summon_drops end
    local overrides = {}
    if drops ~= true then overrides.drops = "none" end
    local positions = C.Geometry.ring_positions(pos, summon.spawn_radius or 100, summon.count or 2)
    for _, spawn_pos in ipairs(positions) do
        if Spawn.count_alive(owner) >= cap then break end
        Spawn.spawn({owner = owner, room_id = room, position = spawn_pos,
            enemy_type = summon.skin or summon.enemy_type or defaults.default_archetype,
            archetype = summon.skin and summon.enemy_type or nil, overrides = overrides})
    end
end

return M
