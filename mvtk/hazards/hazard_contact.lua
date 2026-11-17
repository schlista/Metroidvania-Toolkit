-- Contact policy shared by authored hazards and player rescue policies.
-- No engine or debug dependency is loaded at module scope.
local M = {}
local warned, policies = {}, {}
local modes = {damage=true, safe_return=true, kill=true}

-- A fresh flat engine message; hash userdata is a scalar too.
function M.contact_message(base, mode, lethal, return_damage, identity, rect)
    local out = {}
    for key, value in pairs(base or {}) do
        local kind = type(value)
        if key ~= "instant_kill" and key ~= "instant_amount"
            and (kind == "string" or kind == "number" or kind == "boolean" or kind == "userdata") then
            out[key] = value
        end
    end
    identity, rect = identity or {}, rect or {}
    out.mode, out.lethal, out.return_damage = mode, lethal, return_damage
    out.hazard_id, out.hazard_type = identity.hazard_id, identity.hazard_type
    out.rect_x, out.rect_y = rect.x, rect.y
    out.rect_w, out.rect_h = rect.w or 0, rect.h or 0
    return out
end

function M.normalize_mode(value, name)
    if value == nil or value == "" or value == "none" or value == "type_default" then return nil end
    if modes[value] then return value end
    local key = tostring(name or "hazard") .. ":" .. tostring(value)
    if not warned[key] then
        warned[key] = true
        print("[HAZARD_CONTACT] " .. key .. ": unknown contact mode; inheriting type default")
    end
end

function M.resolve(authored_mode, authored_instant_kill, type_cfg)
    type_cfg = type_cfg or {}
    local mode = M.normalize_mode(authored_mode, type_cfg.name)
        or (authored_instant_kill == true and "kill")
        or M.normalize_mode(type_cfg.on_contact, type_cfg.name)
        or (type_cfg.instant_kill == true and "kill") or "damage"
    local lethal = mode == "kill" or authored_instant_kill == true or type_cfg.instant_kill == true
    if lethal and mode == "damage" then mode = "kill" end
    return mode, lethal
end

function M.settings(config)
    if config == nil then
        config = require("mvtk.core.util").require_config("developer.config.resolved_config") or {}
    end
    local cfg = config.progression and config.progression.hazard_return or {}
    return {enabled=cfg.enabled == true, damage=cfg.damage or 1,
        fade_time=cfg.fade_time or 0.25, grace_time=cfg.grace_time or 1,
        world_bottom_acts_as_pit=cfg.world_bottom_acts_as_pit ~= false}
end

function M.effective(mode, lethal, settings)
    if mode == "safe_return" and not settings.enabled then return lethal and "kill" or "damage" end
    return mode
end

function M.return_damage(authored, type_cfg, settings)
    local value = tonumber(authored)
    if value and value >= 0 then return value end
    value = tonumber((type_cfg or {}).return_damage)
    if value and value >= 0 then return value end
    return (settings or {}).damage or 1
end

-- Hooks are pure transforms, folded in stable id order. Only this seam can
-- rescue a kill; shared gameplay never loads the registering debug module.
function M.register_player_mode(id, fn)
    assert(type(id) == "string" and type(fn) == "function")
    policies[id] = fn
end
function M.unregister_player_mode(id) policies[id] = nil end
function M.player_mode(mode, lethal, damage)
    local ids = {}
    for id in pairs(policies) do ids[#ids+1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do mode, damage = policies[id](mode, lethal, damage) end
    return mode, damage
end

-- A rescue policy can request observation even with authored returns off.
-- The same pure probe is available to later assist policies.
function M.return_sampling_override()
    return M.player_mode("kill", true, 0) == "safe_return"
end
return M
