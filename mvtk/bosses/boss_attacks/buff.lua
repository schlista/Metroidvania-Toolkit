-- Temporary attack buffs compose with the current phase's multipliers.
local C = require "mvtk.bosses.boss_attacks.common"
local M = {}

function M.execute(boss, pattern, instance)
    -- The buff outlives the attack that granted it.
    instance = C.instance(boss, pattern, instance):lasting()
    local buff = pattern.buff or {}
    local duration = buff.duration or C.Defaults.default_buff_duration
    local data = boss.boss_data
    if not data then return end
    C.Runtime.apply_multipliers(boss)
    data.buffs = data.buffs or {}
    local entry = {damage = buff.damage_multiplier, speed = buff.speed_multiplier,
        defense = buff.defense_bonus, instance = instance}
    table.insert(data.buffs, entry)
    C.Runtime.apply_multipliers(boss)
    local function remove()
        for i = #data.buffs, 1, -1 do
            if data.buffs[i] == entry then table.remove(data.buffs, i) end
        end
        C.Runtime.apply_multipliers(boss)
    end
    instance:on_cancel(remove)
    instance:after(duration, function()
        remove()
        instance:on_cancel(nil)
    end)
end

return M
