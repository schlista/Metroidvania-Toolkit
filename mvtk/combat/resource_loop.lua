-- Combat facts refill the shared, transient energy pool in any healing model.
local GameEvents = require "mvtk.core.game_events"
local EnergyState = require "mvtk.player.energy_state"
local M = {}
local tokens = {}

function M.gain_for(event, payload, energy_cfg)
    local cfg, p = energy_cfg or {}, payload or {}
    if cfg.enabled ~= true then return 0 end
    if event == "enemy_damaged" then
        if p.by_player ~= true then return 0 end
        return (p.over_time == true and 0 or math.max(0, tonumber(cfg.gain_on_hit) or 0))
            + (p.defeated == true and math.max(0, tonumber(cfg.gain_on_kill) or 0) or 0)
    elseif event == "player_parried" then
        return math.max(0, tonumber(p.perfect == true and cfg.gain_on_perfect_parry or cfg.gain_on_parry) or 0)
    end
    return 0
end

local function receive(event, payload)
    if not EnergyState.enabled() then return end
    local gain = M.gain_for(event, payload, require("mvtk.player.healing").settings().energy)
    if gain > 0 then EnergyState.add(gain, { reason = "combat" }) end
end

function M.subscribe()
    for _, token in ipairs(tokens) do GameEvents.off(token) end
    tokens = {}
    for _, name in ipairs({ "enemy_damaged", "player_parried" }) do
        local event = name
        tokens[#tokens + 1] = GameEvents.on(event, function(payload) receive(event, payload) end)
    end
end
M.subscribe()
return M
