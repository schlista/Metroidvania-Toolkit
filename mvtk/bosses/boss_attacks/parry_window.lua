--- Boss parry-window attack executor.
-- Opens a counter-attack window. If the boss is hit during the window the
-- boss.boss_data.parry_active flag signals the damage handler to fire the
-- animation and fire `pattern.parry_window.counter_pattern` at the attacker.
-- @module boss_attacks.parry_window

local C = require "mvtk.bosses.boss_attacks.common"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    local pw = pattern.parry_window or {}
    local window = pw.window or C.Defaults.default_parry_window

    C.print(string.format("[BOSS_ATTACKS] Parry window open %.2fs", window))

    local data = boss.boss_data
    if not data or data.defeated then return end
    local generation = (data._parry_generation or 0) + 1
    data._parry_generation = generation
    data.parry_active = true
    data.parry_counter_pattern = pw.counter_pattern
    C.play_resolved_animation(boss, "parry", true)

    instance:on_cancel(function()
        if boss.boss_data == data and data._parry_generation == generation then
            data.parry_active, data.parry_counter_pattern = false, nil
        end
    end)

    instance:after(window, function()
        if boss.boss_data == data and data._parry_generation == generation and data.parry_active then
            data.parry_active = false
            data.parry_counter_pattern = nil
            C.print("[BOSS_ATTACKS] Parry window closed")
        end
        instance:on_cancel(nil)
    end)
end

return M
