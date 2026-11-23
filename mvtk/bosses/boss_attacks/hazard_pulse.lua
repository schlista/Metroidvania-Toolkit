-- Switch on placed hazards for the warning and active window of this cast.
local C = require "mvtk.bosses.boss_attacks.common"
local Arena = require "mvtk.bosses.boss_arena"
local Pulse = require "mvtk.bosses.arena_hazard_pulse"
local Schema = require "mvtk.bosses.attack_pattern_schema"

local M = {}

function M.execute(boss, pattern, instance)
    local arena, reason = C.resolve_arena(boss.config, Arena.get_active_arena())
    local name = pattern._attack_name or "hazard_pulse"
    if not arena then
        if reason ~= "missing" then return end
        boss._hazard_pulse_warnings = boss._hazard_pulse_warnings or {}
        if not boss._hazard_pulse_warnings[name] then
            boss._hazard_pulse_warnings[name] = true
            print(("[BOSS_ATTACKS] Pattern '%s' needs a Boss Arena."):format(name))
        end
        return
    end

    local settings, err = Schema.hazard_pulse_options(pattern, C.Defaults)
    if not settings then print("[BOSS_ATTACKS] " .. err); return end

    local lasting = C.instance(boss, pattern, instance):lasting()
    local started = lasting:time()
    local token = Pulse.start(arena.id, settings.hazard_ids, settings.warn_time, {
        elapsed = boss.boss_data and function() return (boss.boss_data.fight_time or started) - started end,
    })
    local function stop(active)
        Pulse.stop(token)
        active:on_cancel(nil)
    end
    lasting:on_cancel(stop)
    lasting:after(settings.warn_time + settings.duration, stop)
end

return M
