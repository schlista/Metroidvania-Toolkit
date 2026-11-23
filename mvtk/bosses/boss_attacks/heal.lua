--- Boss heal attack executor.
-- Restores health in one or more ticks owned by the attack.
-- @module boss_attacks.heal

local C = require "mvtk.bosses.boss_attacks.common"
local BossManager = require "mvtk.bosses.boss_manager"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    instance.interruptible = true
    local heal = pattern.heal or {}
    local amount = heal.amount
        or (boss.boss_data and boss.boss_data.heal_per_tick)
        or C.Defaults.default_heal_amount or 10
    local ticks = heal.ticks or 1
    local interval = heal.interval or 0.3

    C.print(string.format("[BOSS_ATTACKS] Heal %d x %d (interval %.2f)",
        amount, ticks, interval))

    for i = 1, ticks do
        instance:after(interval * (i - 1), function()
            BossManager.heal_boss(boss.boss_id, amount)
        end)
    end
end

return M
