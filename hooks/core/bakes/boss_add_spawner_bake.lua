local Kit = require "hooks.core.bake_kit"
local M = { TYPES = { "boss_add_spawner" } }

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local props = {
        Kit.text(C, obj, "spawner_id", ""),
        Kit.text(C, obj, "boss_id", ""),
        Kit.text(C, obj, "arena_id", ""),
        Kit.text(C, obj, "enemy_type", "default"),
        Kit.number(C, obj, "spawn_interval", 4),
        Kit.number(C, obj, "spawn_count", 1),
        Kit.number(C, obj, "spawn_radius", 120),
        Kit.number(C, obj, "max_alive", 3),
        Kit.number(C, obj, "max_total", 0),
        Kit.text(C, obj, "active_phases", ""),
        Kit.number(C, obj, "start_delay", 0),
        Kit.bool(C, obj, "start_active", true),
        Kit.bool(C, obj, "despawn_on_defeat", true),
        Kit.text(C, obj, "movement", "type_default"),
        Kit.text(C, obj, "attack_pattern", "type_default"),
        Kit.text(C, obj, "attack_pattern2", "type_default"),
        Kit.number(C, obj, "health_mult", 1),
        Kit.number(C, obj, "damage_mult", 1),
        Kit.number(C, obj, "speed_mult", 1),
        C.text_prop("room_id", room.id, ""),
    }
    for _, prop in ipairs(props) do
        if prop.id == "movement" or prop.id == "attack_pattern" or prop.id == "attack_pattern2" then
            prop.value = Kit.opt(prop.value)
        end
    end
    Kit.instance(C, room, obj_id, "/developer/game/prefabs/boss_add_spawner.go", obj.x, defold_y, props)
    return true
end

return M
