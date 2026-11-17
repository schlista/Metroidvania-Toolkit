-- Pure policy and identity rules shared by runtime and authoring tools.
local M = {}
local POLICIES = {always=true, room_reload=true, save=true, never=true}

local function text(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

function M.is_inherit(value)
    local token = text(value)
    return value == nil or (type(value)=="string" and (token == "" or token == "type_default" or token == "inherit"))
end

function M.valid(value) return POLICIES[text(value)] == true end

-- Unknown instance/type values skip straight to the project default. The second
-- return is for the runtime's once-only warning; authoring reports the source.
function M.resolve_policy(instance_value, type_value, project_default, opts)
    local fallback = M.valid(project_default) and text(project_default) or "room_reload"
    if M.is_inherit(instance_value) and opts and opts.champion == true then return "never" end
    for _, entry in ipairs({{instance_value}, {type_value}}) do
        local value = entry[1]
        if not M.is_inherit(value) then
            if M.valid(value) then return text(value) end
            return fallback, tostring(value)
        end
    end
    return fallback
end

function M.persist_key(defeat_flag, defeat_key)
    local flag, key = text(defeat_flag), text(defeat_key)
    if flag ~= "" then return flag end
    return key ~= "" and ("enemy_defeated_" .. key) or ""
end

function M.effective_defaults(baseline, creator)
    local function merge(dst, src)
        for key,value in pairs(src or {}) do
            if type(value)=="table" then
                dst[key]=merge(type(dst[key])=="table" and dst[key] or {},value)
            else dst[key]=value end
        end
        return dst
    end
    local defaults = merge({},baseline)
    if creator and creator.published == true then
        merge(defaults, (creator.overrides or {}).enemy_defaults or {})
    end
    return defaults
end

-- A run-scoped FreshConfig loader supplies these files. Never package.loaded.
function M.load_configs(load_path)
    return {
        enemy_types=load_path("developer/config/enemy_types.lua") or {},
        enemy_skins=load_path("developer/config/enemy_skins_generated.lua") or {},
        enemy_defaults=M.effective_defaults(load_path("developer/config/enemy_defaults.lua"),
            load_path("developer/config/creator_settings.lua")),
    }
end

function M.for_object(props, configs)
    props, configs = props or {}, configs or {}
    local defaults = configs.enemy_defaults or {}
    local cfg = require("mvtk.enemies.enemy_type_overlay").resolve_with_archetype(
        props.enemy_type, props.archetype, configs.enemy_types or {}, configs.enemy_skins or {},
        {default_archetype=defaults.default_archetype}) or {}
    return M.resolve_policy(props.respawn, cfg.respawn, defaults.respawn_policy, {champion=props.champion})
end

return M
