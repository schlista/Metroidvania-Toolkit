-- One player's shared source table. Safe to require from runtime or editor.
-- The saved ledger is attached lazily; no engine API or script context is used.
local Keys = require "mvtk.player.stat_keys"
local M = { LEASE_TICKS = 3 }
local sources, listeners, warned = {}, {}, {}
local cache, dirty, revision, tick_count, next_listener = {}, true, 0, 0, 0
local ledger, ledger_handle

local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end

local function changed(reason, id)
    dirty, revision = true, revision + 1
    for _, fn in pairs(listeners) do pcall(fn, reason, id) end
end

local function mirror_ledger(reason, id)
    local values = {}
    for key, value in pairs(ledger.totals()) do
        -- The ledger may carry keys whose read sites have not landed yet.
        if Keys.definition(key) and not Keys.effect_error(key, value, "permanent") then values[key] = value end
    end
    sources.ledger = { layer = "permanent", values = values }
    changed(reason or "load", id)
end

local function ensure_ledger()
    if ledger then return end
    ledger = require "mvtk.player.permanent_stats"
    ledger_handle = ledger.register_listener(mirror_ledger)
    mirror_ledger()
end

local function warn(id, key, err)
    warned[id] = warned[id] or {}
    if warned[id][key] then return end
    warned[id][key] = true
    print("[PLAYER_STATS] " .. id .. ": " .. err)
end

local function equal(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

-- composed=true accepts finite non-negative multiplier products from an owner
-- that already validated individual effects. Read sites apply the final bounds.
function M.set_source(id, values, opts)
    ensure_ledger()
    opts = opts or {}
    local layer = opts.layer or "temporary"
    if type(id) ~= "string" or id == "" or type(values) ~= "table" or not Keys.LAYERS[layer] then return false end
    if layer ~= "temporary" and (opts.duration ~= nil or opts.lease) then return false end
    if opts.duration ~= nil and (type(opts.duration) ~= "number" or opts.duration ~= opts.duration
        or opts.duration < 0 or opts.duration == math.huge) then return false end
    if opts.group ~= nil and type(opts.group) ~= "string" then return false end
    local accepted = {}
    for key, value in pairs(values) do
        local err = Keys.effect_error(key, value, layer, opts)
        if err then warn(id, key, err) else accepted[key] = value end
    end
    local old = sources[id]
    local source = { layer = layer, values = accepted, group = opts.group,
        duration = opts.duration, lease = opts.lease == true, refreshed_at = tick_count }
    sources[id] = source
    if not old or old.layer ~= layer or old.group ~= source.group or old.lease ~= source.lease
        or not equal(old.values, accepted) then changed("set", id) end
    return true
end

function M.clear_source(id)
    ensure_ledger()
    if not sources[id] then return false end
    sources[id] = nil
    changed("clear", id)
    return true
end

function M.has_source(id, layer)
    ensure_ledger()
    local source = sources[id]
    return source ~= nil and (layer == nil or source.layer == layer)
end
function M.remaining(id)
    ensure_ledger()
    return sources[id] and sources[id].duration
end

function M.clear_layer(layer)
    ensure_ledger()
    for id, source in pairs(sources) do if source.layer == layer then sources[id] = nil end end
    changed("reset")
end

function M.on_player_reset(reason)
    ensure_ledger()
    if reason == "teleport" then
        for id, source in pairs(sources) do if source.lease then sources[id] = nil end end
        changed("reset")
    elseif reason == "init" or reason == "respawn" or reason == "death" or reason == "final" then
        M.clear_layer("temporary")
    end
end

function M.tick(dt, active)
    if not active then return end
    ensure_ledger()
    tick_count = tick_count + 1
    local expired = {}
    for id, source in pairs(sources) do
        if source.duration then source.duration = math.max(0, source.duration - math.max(0, dt)) end
        if (source.duration and source.duration <= 0)
            or (source.lease and tick_count - source.refreshed_at > M.LEASE_TICKS) then
            expired[#expired + 1] = id
        end
    end
    table.sort(expired)
    for _, id in ipairs(expired) do sources[id] = nil; changed("expire", id) end
end

local function strength(value, kind)
    if kind == "mult" then return value == 0 and math.huge or math.abs(math.log(value)) end
    return math.abs(value)
end

local function combine(a, b, kind)
    if kind == "flag" then return a or b end
    if kind == "add" then return a + b end
    return a * b
end

local function neutral(kind)
    if kind == "flag" then return false end
    return kind == "mult" and 1 or 0
end

local function rebuild()
    ensure_ledger()
    if not dirty then return end
    cache = {}
    local ids, groups = {}, {}
    for id in pairs(sources) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local source = sources[id]
        for key, value in pairs(source.values) do
            local def = Keys.definition(key)
            if source.group then
                groups[key] = groups[key] or {}
                local old = groups[key][source.group]
                if old == nil or (def.kind == "flag" and value)
                    or (def.kind ~= "flag" and strength(value, def.kind) > strength(old, def.kind)) then
                    groups[key][source.group] = value
                end
            else
                if cache[key] == nil then cache[key] = neutral(def.kind) end
                cache[key] = combine(cache[key], value, def.kind)
            end
        end
    end
    for key, values in pairs(groups) do
        local kind = Keys.definition(key).kind
        if cache[key] == nil then cache[key] = neutral(kind) end
        for _, value in pairs(values) do cache[key] = combine(cache[key], value, kind) end
    end
    dirty = false
end

local function clamp(value, def)
    if def.min then value = math.max(def.min, value) end
    if def.max then value = math.min(def.max, value) end
    return value
end

function M.mult(key, sub, fallback_sub)
    rebuild()
    local def = Keys.KEYS[key]
    if not def or def.kind ~= "mult" then return 1 end
    local value = cache[key] or 1
    if def.sub then
        local exact = sub and cache[key .. ":" .. sub]
        local fallback = fallback_sub and cache[key .. ":" .. fallback_sub]
        value = value * (exact or fallback or 1)
    end
    return clamp(value, def)
end

function M.sub_mult(key, sub, fallback_sub)
    local def = Keys.KEYS[key]
    if not def or not def.sub then return 1 end
    return M.mult(key, sub, fallback_sub) / M.mult(key)
end

-- Scale once where damage leaves the player, before hitbox/projectile creation.
function M.outgoing_damage(n)
    if type(n) ~= "number" then return n end
    return n * M.mult("damage_mult")
end

function M.add(key)
    rebuild()
    local def = Keys.KEYS[key]
    return def and def.kind == "add" and clamp(cache[key] or 0, def) or 0
end
function M.flag(key) rebuild(); return cache[key] == true end
function M.totals()
    return { max_health = M.add("max_health"), max_energy = M.add("max_energy"), max_stamina = M.add("max_stamina") }
end
function M.revision() ensure_ledger(); return revision end
function M.describe()
    ensure_ledger()
    local result = {}
    for id, source in pairs(sources) do
        result[#result + 1] = { id = id, layer = source.layer, values = copy(source.values), remaining = source.duration }
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function M.register_listener(fn)
    ensure_ledger()
    if type(fn) ~= "function" then return nil end
    next_listener = next_listener + 1
    listeners[next_listener] = fn
    return next_listener
end
function M.unregister_listener(handle) listeners[handle] = nil end

-- Test-only reset also detaches from the ledger; production owners re-set sources.
function M.reset_all()
    if ledger then ledger.unregister_listener(ledger_handle) end
    ledger, ledger_handle = nil, nil
    sources, listeners, warned, cache = {}, {}, {}, {}
    dirty, revision, tick_count, next_listener = true, 0, 0, 0
end

M.MULTIPLIER_SOURCE = { id = "stats", order = 30, challenge = false, range = { 0, 10 },
    factor = function(channel) if channel == "damage_to_player" then return M.mult("damage_taken_mult") end end }

return M
