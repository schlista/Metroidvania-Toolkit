-- Pure type/affinity rules. Callers supply config; no engine or config loading.
local M = {}

-- Relay defaults are generic physical hits. Other unknown ids stay unknown.
function M.type_id(dtype)
    if dtype == nil or dtype == "" or dtype == "contact" then return "physical" end
    return dtype
end

function M.family(dtype, cfg)
    local entry = (cfg.types or {})[M.type_id(dtype)]
    return entry and entry.family
end

-- Exact -> family -> fallback. Zero is an explicit value, never inheritance.
function M.lookup(values, dtype, cfg, fallback)
    local t = M.type_id(dtype)
    values = values or {}
    local value = values[t]
    if value == nil then
        local family = M.family(t, cfg)
        value = family and values[family]
    end
    if value == nil then return fallback end
    return value
end

-- Text CSV only -> ordered unique array of known ids. No hash reverse maps.
function M.parse_list(text, cfg)
    local result, seen = {}, {}
    if type(text) ~= "string" then return result end
    for word in text:gmatch("[^,]+") do
        local id = word:match("^%s*(.-)%s*$")
        if (cfg.types or {})[id] and not seen[id] then
            result[#result + 1], seen[id] = id, true
        end
    end
    return result
end

local function flags(text, cfg)
    local result = {}
    for _, id in ipairs(M.parse_list(text, cfg)) do result[id] = true end
    return result
end

-- Archetype plus normalized instance values; nil/blank/-1 inherit, numeric 0
-- stays explicit. Flag fields are CSV. tags is an array of target tag ids.
-- factors is an optional ordered array of nonnegative numbers, multiplied in
-- DamageCalc's type step (armor/guard/stagger extensions use this same path).
function M.profile(type_cfg, instance, cfg)
    type_cfg, instance = type_cfg or {}, instance or {}
    local function value(key)
        local v = instance[key]
        if v == nil or v == "" or v == -1 then return type_cfg[key] end
        return v
    end
    local taken = {}
    for id, n in pairs(type_cfg.damage_taken or {}) do taken[id] = n end
    for id, n in pairs(instance.damage_taken or {}) do if n ~= -1 then taken[id] = n end end
    local tags, factors = {}, {}
    for _, tag in ipairs(value("tags") or {}) do tags[#tags + 1] = tag end
    for _, n in ipairs(value("factors") or {}) do factors[#factors + 1] = n end
    return { taken = taken, weak = flags(value("weak_to"), cfg),
        resist = flags(value("resist_to"), cfg), immune = flags(value("immune_to"), cfg),
        only = flags(value("vulnerable_to"), cfg), tags = tags, factors = factors }
end

local function verdict(n)
    if n == 0 then return "immune" end
    if n > 1 then return "weak" end
    if n < 1 then return "resist" end
    return "normal"
end

-- Returns affinity factor, verdict. A restrictive only list and explicit
-- immunity win; numeric damage_taken overrides weak/resist flags. Within each
-- rule try the exact type before its family. Unknown types remain neutral
-- unless the target's only list deliberately excludes them.
function M.multiplier(dtype, profile, cfg)
    local p, t = profile or {}, M.type_id(dtype)
    if next(p.only or {}) and not M.lookup(p.only, t, cfg, false) then return 0, "immune" end
    if M.lookup(p.immune, t, cfg, false) then return 0, "immune" end
    local n = M.lookup(p.taken, t, cfg)
    if n ~= nil then return n, verdict(n) end
    -- An exact affinity wins over a different family affinity.
    for _, id in ipairs({t, M.family(t, cfg)}) do
        if (p.weak or {})[id] then return cfg.weak_multiplier, "weak" end
        if (p.resist or {})[id] then return cfg.resist_multiplier, "resist" end
    end
    return 1, "normal"
end

return M
