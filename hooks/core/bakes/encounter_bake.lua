local Kit = require "hooks.core.bake_kit"
local Links = require "mvtk.tiled.encounter_links"
local M = {TYPES = {"encounter", "encounter_spawn"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local props = {C.text_prop("room_id", room.id, "")}
    local x, y, prototype = tonumber(obj.x) or 0, defold_y
    if obj_type == "encounter" then
        local w, h, sx, sy
        x, y, sx, sy, w, h = Kit.rect(C, room, obj, defold_y, 256, 128, 512, 256)
        local name = room.id .. "_encounter_" .. obj.id .. ".go"
        C.write_if_changed(C.join(C.PATH.generated_go, name),
            C.gen_collision_zone_go("/mvtk/prefabs/encounter_controller.script", w, h, 512, 256, "sensor", {"player"}))
        prototype = C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name
        props[#props+1] = C.text_prop("encounter_id", Links.id(room.id, obj), "")
        props[#props+1] = C.number_prop("width", w, 512)
        props[#props+1] = C.number_prop("height", h, 256)
        for _, row in ipairs({{"encounter_start", "on_enter"}, {"requires_flag", ""},
            {"target_id", ""}, {"clear_flag", ""}, {"clear_message", "open"},
            {"battle_music", ""}, {"victory_music", ""}, {"reward_collectible", ""}}) do
            local prop = Kit.text(C, obj, row[1], row[2])
            if row[1] == "battle_music" or row[1] == "victory_music" or row[1] == "reward_collectible" then
                prop.value = Kit.opt(prop.value)
            end
            props[#props+1] = prop
        end
        for _, row in ipairs({{"start_delay", 0}, {"wave_delay", -1}, {"max_alive", 0}, {"reward_amount", 1}}) do
            props[#props+1] = Kit.number(C, obj, row[1], row[2])
        end
        for _, row in ipairs({{"lock_room", true}, {"enemy_drops", false}, {"show_wave_messages", true}, {"repeatable", false}}) do
            props[#props+1] = Kit.bool(C, obj, row[1], row[2])
        end
    else
        local encounters = Links.collect(room.tiled)
        local id, err = Links.resolve(room.id, obj, encounters)
        if not id then return nil, err end
        props[#props+1] = C.text_prop("encounter_id", id, "")
        props[#props+1] = C.text_prop("spawn_id", obj_id, "")
        for _, row in ipairs({{"enemy_type", "default"}, {"archetype", ""}, {"telegraph_effect", ""}}) do
            local prop = Kit.text(C, obj, row[1], row[2])
            prop.value = Kit.opt(prop.value)
            props[#props+1] = prop
        end
        for _, row in ipairs({{"encounter_wave", 1}, {"spawn_count", 1}, {"size", -1},
            {"spawn_delay", 0}, {"spawn_interval", 0.5}, {"facing", 0}}) do
            props[#props+1] = Kit.number(C, obj, row[1], row[2])
        end
        props[#props+1] = Kit.bool(C, obj, "elite", false)
        prototype = "/developer/game/prefabs/encounter_spawn_marker.go"
    end
    Kit.instance(C, room, obj_id, prototype, x, y, props)
    return true
end

return M
