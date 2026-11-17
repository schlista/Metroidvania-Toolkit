-- Shared range-interaction station bake; later station kinds extend TYPES.
local Kit = require "hooks.core.bake_kit"
local M = {TYPES = {"shop", "upgrade_station", "skill_trainer", "offering_altar", "bank"}}
local KINDS = {
    bank = { prompt = "Bank", prefab = "/developer/game/prefabs/bank.go" },
    offering_altar = { prompt = "Offer", prefab = "/developer/game/prefabs/offering_altar.go" },
    skill_trainer = { leaf = "trainer_catalog", catalog = "training_hall", prompt = "Train", prefab = "/developer/game/prefabs/skill_trainer.go" },
    shop = { leaf = "shop_id", catalog = "town_vendor", prompt = "Shop", prefab = "/developer/game/prefabs/shop.go" },
    upgrade_station = { leaf = "upgrade_catalog", catalog = "forge", prompt = "Upgrade", prefab = "/developer/game/prefabs/upgrade_station.go" },
}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local kind = KINDS[obj_type] or KINDS.shop
    local catalog = kind.leaf and Kit.text(C, obj, kind.leaf, kind.catalog) or C.text_prop("catalog_id", "")
    catalog.id, catalog.value = "catalog_id", Kit.opt(catalog.value)
    local props = {
        C.text_prop("station_kind", obj_type), C.text_prop("station_id", obj_id), catalog,
        Kit.text(C, obj, "prompt_text", kind.prompt), Kit.text(C, obj, "menu_title", ""),
        Kit.text(C, obj, "requires_flag", ""), Kit.text(C, obj, "locked_text", ""),
        C.text_prop("room_id", room.id), Kit.number(C, obj, "range", 96),
        Kit.bool(C, obj, "show_on_map", true),
    }
    if obj_type == "bank" then
        props[2] = Kit.text(C, obj, "bank_id", "")
        props[2].id, props[2].value = "station_id", Kit.opt(props[2].value)
        if props[2].value == "" then props[2].value = obj_id end
        local mode = Kit.text(C, obj, "bank_mode", "both")
        mode.value = Kit.opt(mode.value)
        props[#props + 1] = mode
    end
    if obj_type == "offering_altar" then
        props[2] = Kit.text(C, obj, "altar_id", "")
        props[2].id, props[2].value = "station_id", Kit.opt(props[2].value)
        if props[2].value == "" then props[2].value = obj_id end
        for _, field in ipairs({{"cost_currency", 0}, {"cost_item_count", 1}}) do
            local prop = Kit.number(C, obj, field[1], field[2])
            prop.id = "offer_" .. field[1]; props[#props + 1] = prop
        end
        for _, name in ipairs({"cost_item", "reward", "reward_text", "set_flag"}) do
            local prop = Kit.text(C, obj, name, "")
            prop.id = "offer_" .. name; props[#props + 1] = prop
        end
        local remove = Kit.bool(C, obj, "remove_after_use", false)
        remove.id = "offer_remove_after_use"; props[#props + 1] = remove
    end
    if obj_type == "skill_trainer" then
        props[#props + 1] = Kit.bool(C, obj, "leave_when_done", false)
    end
    if obj_type == "shop" then
        props[#props + 1] = Kit.bool(C, obj, "buys_items", true)
        props[#props + 1] = Kit.number(C, obj, "sell_share", -1)
    end
    local prototype = C.visual_helpers.resolve_visual_proto(room.id, obj, obj_type,
        kind.prefab)
    Kit.instance(C, room, obj_id, prototype, obj.x, defold_y, props)
    return true
end
return M
