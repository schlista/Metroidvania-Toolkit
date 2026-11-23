--- Boss hazard attack executor.
-- A hazard with no named mechanic keeps its original one-shot area hit.
-- @module boss_attacks.hazard

local C = require "mvtk.bosses.boss_attacks.common"
local AOE  = require "mvtk.bosses.boss_attacks.aoe"
local Indicator = require "mvtk.bosses.indicator_geometry"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    local hazard = pattern.hazard or {}
    if hazard.type ~= nil then return end
    C.print("[BOSS_ATTACKS] Hazard attack: generic")
    return AOE.execute(boss, Indicator.hazard_attack(pattern, C.Defaults), instance, pattern)
end

return M
