-- Weapon ownership is Inventory plus one virtual starter. Providers never grant.
-- State changes ride the next ordinary save; restoration is silent and idempotent.
local Util = require "mvtk.core.util"
local Inventory = require "mvtk.core.inventory"
local Events = require "mvtk.core.game_events"
local Ability = require "mvtk.abilities.ability_manager"
local RuntimeSettings = require "developer.config.runtime_settings"
local Baseline = require "developer.config.weapons"
local M = {}
local cached, settings_revision, by_id
local equipped, revision = nil, 0
local tiers = {}
local added_listener, removed_listener

function M.settings()
    local current = RuntimeSettings.revision()
    if not cached or settings_revision ~= current then
        cached, settings_revision, by_id = RuntimeSettings.section("weapons", Baseline), current, {}
        for _, entry in ipairs(cached.weapons or {}) do by_id[entry.id] = entry end
    end
    return cached
end
function M.enabled() return M.settings().enabled == true end
local function starter()
    local id = M.settings().starting_weapon
    return by_id[id] and id or nil
end
function M.owns(id)
    M.settings()
    return by_id[id] ~= nil and (id == starter() or Inventory.has("weapon_" .. id, 1))
end
local function usable(id)
    local entry = by_id[id]
    return entry ~= nil and M.owns(id) and (not entry.requires_ability
        or entry.requires_ability == "" or Ability.is_ability_unlocked(entry.requires_ability))
end
local function fallback()
    local id = starter()
    return usable(id) and id or nil
end
local function set_equipped(id)
    if equipped ~= id then equipped, revision = id, revision + 1 end
end
function M.current()
    if not M.enabled() then return nil end
    if not usable(equipped) then set_equipped(fallback()) end
    return by_id[equipped]
end
function M.equip(id)
    if not M.enabled() or not usable(id) then return false end
    set_equipped(id)
    M.publish()
    return true
end
function M.cycle(dir)
    if not M.enabled() then return false end
    local owned, index = {}, nil
    M.current()
    for _, entry in ipairs(cached.weapons or {}) do
        if usable(entry.id) then
            owned[#owned + 1] = entry.id
            if equipped == entry.id then index = #owned end
        end
    end
    if #owned == 0 then return false end
    local step = (tonumber(dir) or 1) < 0 and -1 or 1
    index = index or (step == 1 and 0 or 1)
    return M.equip(owned[((index - 1 + step) % #owned) + 1])
end
function M.publish()
    local entry = M.current()
    require("mvtk.ui.hud_bus").post("weapon", entry and {
        name = {text=entry.name},
        icon = {texture="gameplay_visuals", anim=entry.icon_animation or "prop_base"},
    } or {})
end
function M.revision() return revision end
-- Tier 1 is the base; catalog tiers[1] describes tier 2. Silent for transaction undo.
function M.tier(id) return tiers[id] or 1 end
function M.set_tier(id, n)
    M.settings()
    local entry = by_id[id]
    if not entry or type(n) ~= "number" or n ~= math.floor(n) or n < 1
        or (n > 1 and (type(entry.tiers) ~= "table" or type(entry.tiers[n-1]) ~= "table")) then return false end
    if M.tier(id) ~= n then tiers[id], revision = n > 1 and n or nil, revision + 1 end
    return true
end
local function restore_tiers(saved)
    local next_tiers = {}
    for id, n in pairs(type(saved) == "table" and saved or {}) do
        local entry = by_id[id]
        if entry and type(n) == "number" and n == math.floor(n) and n > 1
            and type(entry.tiers) == "table" and type(entry.tiers[n-1]) == "table" then next_tiers[id] = n end
    end
    for id, n in pairs(tiers) do if next_tiers[id] ~= n then revision = revision + 1; break end end
    for id, n in pairs(next_tiers) do if tiers[id] ~= n then revision = revision + 1; break end end
    tiers = next_tiers
end
local provider = {
    version = 1, order = 46, description = "Equipped weapon",
    capture = function()
        local data = {equipped = equipped}
        if next(tiers) then data.tiers = Util.deep_copy(tiers) end
        return data
    end,
    apply = function(data)
        M.settings()
        local id = type(data) == "table" and data.equipped or nil
        restore_tiers(type(data) == "table" and data.tiers or nil)
        set_equipped(usable(id) and id or fallback())
    end,
    defaults = function() M.settings(); restore_tiers(nil); set_equipped(fallback()) end,
}
function M.ensure_checkpoint_provider()
    return Util.register_checkpoint_provider("weapons", provider)
end
local function listen()
    if not added_listener or not added_listener.active then
        added_listener = Events.on("item_added", function(event)
            if not M.enabled() then return end
            local id = event.item_id:match("^weapon_(.+)$")
            if not id or not by_id[id] or id == starter() or event.total ~= event.count then return end
            -- A virtual starter does not consume the first owned weapon's auto-equip.
            local first = true
            for _, entry in ipairs(cached.weapons or {}) do
                if entry.id ~= id and entry.id ~= starter() and Inventory.has("weapon_" .. entry.id, 1) then
                    first = false; break
                end
            end
            if first then M.equip(id) end
            local entry = by_id[id]
            require("mvtk.ui.notices").post({kind = "weapon", key = "weapon:" .. id,
                title = {key = "notice.new_weapon"}, text = {text = entry.name},
                icon = {texture = "gameplay_visuals", anim = entry.icon_animation or "prop_base"}})
        end)
    end
    if not removed_listener or not removed_listener.active then
        removed_listener = Events.on("item_removed", function(event)
            if event.item_id == "weapon_" .. (equipped or "") and not M.owns(equipped) then
                set_equipped(fallback())
                M.publish()
            end
        end)
    end
end
function M.on_session_start()
    listen()
    -- Provider restore already selected the saved weapon. Do not post acquisition.
    M.publish()
end
require("mvtk.player.loadout").register("weapons", {
    label = {key="inventory.weapons"},
    active = function()
        if not M.enabled() or not M.settings().quick_switch then return false end
        local count = 0
        for _, entry in ipairs(cached.weapons or {}) do
            if M.owns(entry.id) then count = count + 1 end
        end
        return count >= 2
    end,
    cycle = function() return M.cycle(1) end,
})
require("mvtk.core.input_bindings").show_row("loadout_cycle", function()
    return M.enabled() and M.settings().quick_switch == true
end)
M.ensure_checkpoint_provider()
listen()
return M
