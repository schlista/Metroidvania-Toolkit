-- Inventory owns charms and slot items; only the ordered equipped ids are saved here.
-- Equipment changes ride the next save. Restore never grants, emits or posts notices.
local Util = require "mvtk.core.util"
local Inventory = require "mvtk.core.inventory"
local Events = require "mvtk.core.game_events"
local Stats = require "mvtk.player.player_stats"
local Keys = require "mvtk.player.stat_keys"
local RuntimeSettings = require "developer.config.runtime_settings"
local Baseline = require "developer.config.charms"
local M = {}
local cached, settings_revision, by_id
local equipped, revision = {}, 0
local added_listener, removed_listener
local warned_capacity = false

function M.settings()
    local current = RuntimeSettings.revision()
    if not cached or settings_revision ~= current then
        cached, settings_revision, by_id = RuntimeSettings.section("charms", Baseline), current, {}
        for _, entry in ipairs(cached.charms or {}) do by_id[entry.id] = entry end
    end
    return cached
end
function M.enabled() return M.settings().enabled == true end
function M.owns(id)
    M.settings()
    return by_id[id] ~= nil and Inventory.count("charm_" .. id) > 0
end
function M.capacity()
    local cfg = M.settings()
    return math.min(cfg.max_slots, cfg.base_slots + Inventory.count(cfg.slot_item))
end
function M.equipped()
    local ids = {}
    for i, id in ipairs(equipped) do ids[i] = id end
    return ids
end
function M.is_equipped(id)
    for _, value in ipairs(equipped) do if value == id then return true end end
    return false
end
function M.used_slots()
    M.settings()
    local used = 0
    for _, id in ipairs(equipped) do used = used + (by_id[id] and by_id[id].cost or 0) end
    return used
end
local function publish()
    local summed = {}
    if M.enabled() then
        for _, id in ipairs(equipped) do
            for key, value in pairs(by_id[id].effects) do
                local def = Keys.definition(key)
                if key ~= "invulnerable" and def and not Keys.effect_error(key, value, "equipment") then
                    if def.kind == "add" then summed[key] = (summed[key] or 0) + value
                    elseif def.kind == "mult" then summed[key] = (summed[key] or 1) * value end
                end
            end
        end
    end
    -- PlayerStats compares source values before notifying resource/stat listeners.
    -- Re-setting also repairs a source cleared externally, without equip/heal churn.
    Stats.set_source("charms", summed, {layer = "equipment", composed = true})
end
local function set_equipped(ids)
    if #equipped ~= #ids or table.concat(equipped, "\n") ~= table.concat(ids, "\n") then
        equipped, revision = ids, revision + 1
    end
    publish()
end
local function normalize(ids)
    M.settings()
    local result, seen, used, trimmed = {}, {}, 0, false
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        if type(id) == "string" and not seen[id] and M.owns(id) then
            result[#result + 1], seen[id], used = id, true, used + by_id[id].cost
        end
    end
    local capacity = M.capacity()
    while used > capacity and #result > 0 do
        used = used - by_id[result[#result]].cost
        result[#result], trimmed = nil, true
    end
    return result, trimmed
end
function M.equip(id)
    if not M.enabled() or not M.owns(id) then return false end
    if M.is_equipped(id) then return true end
    if M.used_slots() + by_id[id].cost > M.capacity() then return false end
    local ids = M.equipped(); ids[#ids + 1] = id; set_equipped(ids)
    return true
end
function M.unequip(id)
    if not M.enabled() or not M.is_equipped(id) then return false end
    local ids = {}
    for _, value in ipairs(equipped) do if value ~= id then ids[#ids + 1] = value end end
    set_equipped(ids)
    return true
end
function M.revision() return revision end
local provider = {
    version = 1, order = 47, description = "Equipped charms",
    capture = function() return {equipped = M.equipped()} end,
    apply = function(data)
        local ids, trimmed = normalize(type(data) == "table" and data.equipped)
        set_equipped(ids)
        if trimmed and not warned_capacity then
            warned_capacity = true
            print("[CHARMS] Removed last-equipped charms to fit slot capacity.")
        end
    end,
    defaults = function() M.settings(); warned_capacity = false; set_equipped({}) end,
}
function M.ensure_checkpoint_provider()
    return Util.register_checkpoint_provider("charms", provider)
end
local function listen()
    if not added_listener or not added_listener.active then
        added_listener = Events.on("item_added", function(event)
            if not M.enabled() then return end
            local id = event.item_id:match("^charm_(.+)$")
            if not id or not by_id[id] or event.total ~= event.count then return end
            local entry = by_id[id]
            require("mvtk.ui.notices").post({kind = "charm", key = "charm:" .. id,
                title = {key = "notice.new_charm"}, text = {text = entry.name},
                icon = {texture = "gameplay_visuals", anim = entry.icon_animation or "prop_base"}})
        end)
    end
    if not removed_listener or not removed_listener.active then
        removed_listener = Events.on("item_removed", function(event)
            local cfg = M.settings()
            if event.item_id == cfg.slot_item or event.item_id:sub(1, 6) == "charm_" then
                set_equipped((normalize(equipped)))
            end
        end)
    end
end
function M.on_session_start()
    listen()
    set_equipped((normalize(equipped)))
end
M.ensure_checkpoint_provider()
listen()
return M
