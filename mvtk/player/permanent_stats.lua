-- Saved permanent bonuses, independent of the player instance and script context.
-- Keys: pickup:<collectible id>, upgrade:<id>, fragment:<group>:<n>.
-- Grant units use pickup:grant:<once_key or instance_id>, then #n per unit.
-- Pickup keys are stable only for baked collectibles (their instance names).
-- Runtime containers use CollectibleManager.generate_id's timestamped identity,
-- so each newly spawned container can grant a new bonus.
local Util = require "mvtk.core.util"

local M = {}
local entries = {}
local listeners = {}
local next_listener = 0
local upgrade_resolver
local hydrated = false
local additive_keys = { "max_health", "max_energy", "max_stamina" }

local function copy_deltas(source)
    local result = {}
    if type(source) ~= "table" then return result end
    for _, key in ipairs({ "max_health", "max_energy", "max_stamina", "damage_mult" }) do
        local value = source[key]
        if type(value) == "number" and value == value and math.abs(value) < math.huge then
            result[key] = value
        end
    end
    return result
end

local function copy_entries(source)
    local result = {}
    for key, entry in pairs(type(source) == "table" and source or {}) do
        if type(key) == "string" and type(entry) == "table"
            and type(entry.kind) == "string" and type(entry.id) == "string" then
            result[key] = { kind = entry.kind, id = entry.id, deltas = copy_deltas(entry.deltas) }
        end
    end
    return result
end

local function notify(reason, key)
    for _, listener in pairs(listeners) do
        pcall(listener, reason, key)
    end
end

local function apply(payload)
    entries = copy_entries(type(payload) == "table" and payload.entries)
    hydrated = true
    notify("load")
end

local function ensure_hydrated()
    -- An explicitly emptied ledger must not resurrect stale checkpoint entries.
    if hydrated or next(entries) then return end
    local ok, Checkpoint = pcall(require, "mvtk.core.checkpoint")
    local data = ok and Checkpoint.data
    local envelope = data and data.modules and data.modules.permanent_stats
    if type(envelope) == "table" and type(envelope.data) == "table" then
        apply(envelope.data)
    end
end

function M.record(key, entry)
    ensure_hydrated()
    if type(key) ~= "string" or key == "" or entries[key] then return false end
    local copied = copy_entries({ [key] = entry })
    if not copied[key] then return false end
    entries[key] = copied[key]
    hydrated = true
    notify("record", key)
    return true
end

function M.forget(key)
    ensure_hydrated()
    if not entries[key] then return false end
    entries[key] = nil
    hydrated = true
    notify("forget", key)
    return true
end

function M.has(key)
    ensure_hydrated()
    return entries[key] ~= nil
end

function M.totals()
    ensure_hydrated()
    local result = { max_health = 0, max_energy = 0, max_stamina = 0, damage_mult = 1 }
    for _, entry in pairs(entries) do
        local deltas = entry.deltas
        if entry.kind == "upgrade" and upgrade_resolver then
            local resolved = upgrade_resolver(entry.id)
            if type(resolved) == "table" then deltas = copy_deltas(resolved) end
        end
        for _, key in ipairs(additive_keys) do
            result[key] = result[key] + (deltas[key] or 0)
        end
        result.damage_mult = result.damage_mult * (deltas.damage_mult or 1)
    end
    return result
end

function M.set_upgrade_resolver(fn)
    upgrade_resolver = fn
    notify("resolver")
end

function M.register_listener(fn)
    if type(fn) ~= "function" then return nil end
    next_listener = next_listener + 1
    listeners[next_listener] = fn
    return next_listener
end

function M.unregister_listener(handle)
    listeners[handle] = nil
end

-- Test reset; provider defaults preserve bindings and the installed resolver.
function M.clear()
    entries, listeners = {}, {}
    upgrade_resolver = nil
    hydrated = true
end

Util.register_checkpoint_provider("permanent_stats", {
    version = 1,
    order = 44,
    description = "Permanent stat bonuses",
    capture = function()
        ensure_hydrated()
        return { entries = copy_entries(entries) }
    end,
    apply = apply,
    defaults = function() apply({}) end,
})
ensure_hydrated()

return M
