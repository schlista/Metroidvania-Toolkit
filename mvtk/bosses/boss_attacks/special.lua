--- Boss "special" attack executor.
-- Routes legacy aliases (charge / hazard / combo) and the per-pattern
-- callback escape hatch. Named specials resolve before reaching dispatch.
-- @module boss_attacks.special

local C = require "mvtk.bosses.boss_attacks.common"
local Charge = require "mvtk.bosses.boss_attacks.charge"
local Hazard = require "mvtk.bosses.boss_attacks.hazard"
local Combo  = require "mvtk.bosses.boss_attacks.combo"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    if pattern.type == "charge" then
        return Charge.execute(boss, pattern, instance)
    end
    if pattern.type == "hazard" then
        return Hazard.execute(boss, pattern, instance)
    end
    if pattern.type == "combo" then
        return Combo.execute(boss, pattern, instance)
    end

    local special = pattern.special or {}
    if type(special.callback) == "function" then
        pcall(special.callback, boss, pattern)
        return
    end

end

return M
