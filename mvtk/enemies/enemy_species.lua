-- Pure species identities shared by the census and enemy lifecycle services.
local M = {}
function M.resolve(props)
    props = props or {}
    for _, key in ipairs({"species", "enemy_type", "archetype", "skin"}) do
        local value = props[key]
        if value ~= nil then
            local text = tostring(value):match("^%s*(.-)%s*$")
            if text ~= "" then return text end
        end
    end
    return "unknown"
end
-- Identity part of summon tuning. Accept flat census properties or normalized
-- runtime overrides without importing the normalizer back into this leaf module.
function M.summon_identity(overrides, preset, defaults, types)
    local function optional(value)
        if value == nil then return nil end
        local token = tostring(value):match("^%s*(.-)%s*$"):lower()
        if token == "" or token == "none" or token == "type_default" or token == "inherit" then return nil end
        return value
    end
    local tuning = {}
    for k,v in pairs((defaults or {}).summon or {}) do tuning[k] = v end
    for k,v in pairs((preset or {}).summon or {}) do tuning[k] = v end
    for _,key in ipairs({"enemy_type", "archetype"}) do
        local value = (overrides or {})["summon_" .. key]
        -- Match the runtime normalizer: only non-sentinel, trimmed text overrides.
        value = optional(type(value)=="string" and value:match("^%s*(.-)%s*$") or nil)
        if value ~= nil then tuning[key] = value end
    end
    local archetype = optional(tuning.archetype)
    return optional(tuning.enemy_type) or optional(((types or {})[archetype] or {}).skin) or "default", archetype
end

function M.from_object(kind, props, configs)
    props, configs = props or {}, configs or {}
    if kind == "encounter_spawn" or kind == "boss_add_spawner" then
        return {}, {M.resolve({enemy_type=props.enemy_type, archetype=props.archetype})}
    end
    if kind ~= "enemy" then return {}, {} end
    local placed, spawned = {M.resolve(props)}, {}
    local defaults, types = configs.enemy_defaults or {}, configs.enemy_types or {}
    local cfg = require("mvtk.enemies.enemy_type_overlay").resolve_with_archetype(
        props.enemy_type, props.archetype, types, configs.enemy_skins or {},
        {default_archetype=defaults.default_archetype}) or {}
    if defaults.summon and (props.archetype == "summoner" or props.archetype == "nest"
        or props.enemy_type == "summoner" or props.enemy_type == "nest" or cfg.summon) then
        local enemy_type, archetype = M.summon_identity(props, cfg, defaults, types)
        spawned[1] = M.resolve({enemy_type=enemy_type, archetype=archetype})
    end
    return placed, spawned
end
return M
