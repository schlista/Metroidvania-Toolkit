-- Shared multiplier sources. Loading this module is safe in the editor;
-- source modules are pulled only when a value is requested.
-- Not a literal require: its sources require this module, and Bob refuses require cycles.
local SOURCES_MODULE = "mvtk.combat.multiplier_sources"
local M = {}
M.CHANNELS = {
    "damage_to_player", "damage_to_enemy", "damage_to_boss",
    "enemy_health", "boss_health", "loot",
}

local keys = {
    damage_to_player = "damage_taken_mult",
    damage_to_enemy = "damage_dealt_mult",
    damage_to_boss = "damage_dealt_mult",
    enemy_health = "enemy_health_mult",
    boss_health = "boss_health_mult",
    loot = "loot_mult",
}
local sources, ordered, warned = {}, {}, {}
local ready, dirty = false, false

local function check_channel(channel)
    assert(keys[channel], "Unknown multiplier channel: " .. tostring(channel))
end

function M.register_source(def)
    assert(type(def) == "table" and type(def.id) == "string" and def.id ~= "",
        "Multiplier source needs an id")
    sources[def.id] = def
    dirty = true
end

function M.unregister_source(id)
    sources[id] = nil
    dirty = true
end

local function ensure_sources()
    if not ready then
        local list = require(SOURCES_MODULE)
        for _, owner in ipairs(list) do M.register_source(owner.MULTIPLIER_SOURCE) end
        ready = true
    end
    if dirty then
        ordered = {}
        for _, def in pairs(sources) do ordered[#ordered + 1] = def end
        table.sort(ordered, function(a, b)
            local ao, bo = a.order or 0, b.order or 0
            if ao == bo then return a.id < b.id end
            return ao < bo
        end)
        dirty = false
    end
end

local function factor(def, channel)
    local value = def.factor and def.factor(channel)
    if value == nil then value = 1 end
    if type(value) ~= "number" or value ~= value or value == math.huge
        or value == -math.huge or value < 0 then
        warned[def.id] = warned[def.id] or {}
        if not warned[def.id][channel] then
            warned[def.id][channel] = true
            print("[MULTIPLIERS] Invalid factor from " .. tostring(def.id)
                .. " for " .. tostring(channel) .. ": " .. tostring(value))
        end
        value = 1
    end
    if def.range then value = math.max(def.range[1], math.min(def.range[2], value)) end
    return value
end

function M.get(channel, opts)
    check_channel(channel)
    ensure_sources()
    local product = 1
    for _, def in ipairs(ordered) do
        if not (opts and opts.challenge_only) or def.challenge == true then
            product = product * factor(def, channel)
        end
    end
    return product
end

function M.breakdown(channel)
    check_channel(channel)
    ensure_sources()
    local rows = {}
    for _, def in ipairs(ordered) do
        rows[#rows + 1] = { id = def.id, factor = factor(def, channel) }
    end
    return rows
end

function M.immune_all()
    ensure_sources()
    for _, def in ipairs(ordered) do
        if def.immune_all and def.immune_all() then return true end
    end
    return false
end

function M.challenge_rating()
    return M.get("damage_to_player", { challenge_only = true })
end

function M.scale_amount(channel, n)
    check_channel(channel)
    if n <= 0 then return n end
    return math.max(1, math.floor(n * M.get(channel) + 0.5))
end

function M.table_factor(tbl, channel)
    check_channel(channel)
    if not tbl then return 1 end
    local value = tbl[keys[channel]]
    if value == nil and channel == "boss_health" then value = tbl.enemy_health_mult end
    if value == nil then return 1 end
    return value
end

return M
