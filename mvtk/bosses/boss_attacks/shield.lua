--- Boss shield attack executor.
-- Adds a damage-absorb HP pool that must be depleted before further hits
-- reach the boss. boss.boss_data.shield_hp is read by the
-- boss damage handler. Automatically drops when depleted or on timeout.
-- @module boss_attacks.shield

local C = require "mvtk.bosses.boss_attacks.common"

local M = {}

function M.execute(boss, pattern, instance)
    -- The shield outlives the attack that raised it.
    instance = C.instance(boss, pattern, instance):lasting()
    local shield = pattern.shield or {}
    local shield_hp = shield.hp or C.Defaults.default_shield_hp
    local duration = shield.duration or C.Defaults.default_shield_duration

    C.print(string.format("[BOSS_ATTACKS] Shield up: %d HP / %.1fs", shield_hp, duration))

    local data = boss.boss_data
    if not data or data.defeated then return end
    local generation = (data._shield_generation or 0) + 1
    data._shield_generation = generation
    data.shield_hp, data.shield_max = shield_hp, shield_hp
    -- Informational timestamp; attack instance is the expiry authority.
    data.shield_expires_at = require("mvtk.core.time").gettime() + duration
    C.play_resolved_animation(boss, "shield_up", true)

    instance:on_cancel(function()
        if boss.boss_data == data and data._shield_generation == generation then
            data.shield_hp, data.shield_expires_at = 0, nil
        end
    end)

    instance:after(duration, function()
        if boss.boss_data == data and not data.defeated and data._shield_generation == generation
            and (data.shield_hp or 0) > 0 then
            data.shield_hp, data.shield_expires_at = 0, nil
            C.play_resolved_animation(boss, "shield_down", true)
            C.print("[BOSS_ATTACKS] Shield expired")
        end
        instance:on_cancel(nil)
    end)
end

return M
