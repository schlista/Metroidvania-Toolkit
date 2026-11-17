-- mvtk/enemies/enemy_type_overlay.lua
--
-- Resolves enemy_type ids against authored enemy_types.lua entries plus the
-- generated enemy skin manifest. An optional archetype selects stats and
-- behaviour independently of art. Skin-only ids inherit the configured default.

local M = {}

M.DEFAULT_SKIN_BASE_TYPE = "slime"

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deep_copy(v)
    end
    return out
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function skin_value_is_unset(value)
    if value == nil then
        return true
    end
    local s = trim(value)
    return s == "" or s:lower() == "none"
end

local function get_skins_table(manifest)
    if type(manifest) ~= "table" then
        return {}
    end
    if type(manifest.skins) == "table" then
        return manifest.skins
    end
    return manifest
end

local function cache_get(cache, key)
    if type(cache) ~= "table" then
        return nil, false
    end
    local value = cache[key]
    if value ~= nil then
        return value ~= false and value or nil, true
    end
    return nil, false
end

local function cache_put(cache, key, value)
    if type(cache) == "table" then
        cache[key] = value or false
    end
    return value
end

local function log_synthesized(opts, enemy_type, base_type)
    local logger = opts and opts.logger
    if type(logger) == "function" then
        logger(string.format("enemy_type '%s' synthesized from '%s' (skin-only type)",
            tostring(enemy_type), tostring(base_type)))
    end
end

local function optional_archetype(value)
    local key = trim(value)
    if key == "" or key == "none" or key == "type_default" or key == "inherit" then return nil end
    return key
end

function M.resolve_with_archetype(enemy_type, archetype, base_types, skins_manifest, opts)
    local key = trim(enemy_type)
    archetype = optional_archetype(archetype)
    if type(base_types) ~= "table" or (key == "" and not archetype) then
        return nil
    end
    local default = optional_archetype(opts and opts.default_archetype) or M.DEFAULT_SKIN_BASE_TYPE
    local cache_key = key .. "|" .. (archetype or "") .. "|" .. default
    local cached, hit = cache_get(opts and opts.cache, cache_key)
    if hit then
        return cached
    end

    local skins = get_skins_table(skins_manifest)
    local has_skin = type(skins[key]) == "table"

    if archetype then
        if type(base_types[archetype]) == "table" then
            local cfg = deep_copy(base_types[archetype])
            if has_skin then cfg.skin = key end
            cfg._archetype = archetype
            return cache_put(opts and opts.cache, cache_key, cfg)
        elseif opts and type(opts.logger) == "function" then
            opts.logger("Unknown enemy archetype '" .. archetype .. "'; using art resolution")
        end
    end

    local base_cfg = base_types[key]
    if type(base_cfg) == "table" then
        local cfg = deep_copy(base_cfg)
        if has_skin and skin_value_is_unset(cfg.skin) then
            cfg.skin = key
        end
        return cache_put(opts and opts.cache, cache_key, cfg)
    end

    if has_skin then
        local fallback = base_types[default]
        local stale_default = type(fallback) ~= "table"
        if stale_default then
            if opts and type(opts.logger) == "function" then
                opts.logger("Unknown default enemy archetype '" .. default .. "'; using '" .. M.DEFAULT_SKIN_BASE_TYPE .. "'")
            end
            default = M.DEFAULT_SKIN_BASE_TYPE
            fallback = base_types[default]
        end
        if type(fallback) == "table" then
            local cfg = deep_copy(fallback)
            cfg.skin = key
            cfg.color = nil
            cfg._synthesized_from = default
            if not stale_default then log_synthesized(opts, key, default) end
            return cache_put(opts and opts.cache, cache_key, cfg)
        end
    end

    return cache_put(opts and opts.cache, cache_key, nil)
end

function M.resolve(enemy_type, base_types, skins_manifest, opts)
    return M.resolve_with_archetype(enemy_type, nil, base_types, skins_manifest, opts)
end

return M
