-- Pure pedestal bake; the linked Encounter owns all wave spawning.
local Kit = require "hooks.core.bake_kit"
local Links = require "mvtk.tiled.encounter_links"
local Proto = require "mvtk.editor.proto_emit"
local M = {TYPES = {"combat_trial"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local encounters = Links.collect(room.tiled)
    local encounter_id, err = Links.resolve(room.id, obj, encounters)
    if not encounter_id then return nil, err end
    local id = C.get_prop_value(obj, "trial_id")
    id = type(id) == "string" and id:match("^%s*(.-)%s*$") or ""
    if id == "" then
        id = Proto.generated_object_id(room.id, "combat_trial", obj.id)
    end
    local props = {C.text_prop("room_id", room.id, ""), C.text_prop("trial_id", id, ""),
        C.text_prop("encounter_id", encounter_id, "")}
    for _, row in ipairs({{"trial_name", ""}, {"label", "Begin trial"}, {"trial_goal", "clear"},
        {"trial_reward", ""}, {"clear_flag", ""}, {"requires_flag", ""},
        {"disabled_abilities", ""}, {"disabled_attacks", ""}}) do
        props[#props+1] = Kit.text(C, obj, row[1], row[2])
    end
    for _, row in ipairs({{"range", 96}, {"defeat_target", 10}, {"time_limit", 0},
        {"rank_1", -1}, {"rank_2", -1}, {"rank_3", -1}}) do
        props[#props+1] = Kit.number(C, obj, row[1], row[2])
    end
    props[#props+1] = Kit.bool(C, obj, "no_damage", false)
    local prototype = C.visual_helpers.resolve_visual_proto(room.id, obj, obj_type,
        "/developer/game/prefabs/combat_trial.go")
    Kit.instance(C, room, obj_id, prototype, obj.x, defold_y, props)
    return true
end
return M
