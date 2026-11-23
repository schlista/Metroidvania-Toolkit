--- Boss arena effect attack executor.
-- Applies effects to the active encounter and owns their timed cleanup.
-- @module boss_attacks.environmental

local C = require "mvtk.bosses.boss_attacks.common"
local BossArena = require "mvtk.bosses.boss_arena"
local Schema = require "mvtk.bosses.attack_pattern_schema"

local M = {}

function M.execute(boss, pattern, instance)
    local arena = C.resolve_arena(boss.config, BossArena.get_active_arena())
    if not arena then return end

    local env = pattern.environmental
    if type(env) ~= "table" or type(env.effect_ids) ~= "table" then return end
    instance = C.instance(boss, pattern, instance)
    local params = {
        screen_shake = type(env.shake) == "table" and env.shake or nil,
        flash = type(env.flash) == "table" and env.flash or nil,
    }
    local applied = {}
    for _, effect_id in ipairs(env.effect_ids) do
        if Schema.ENVIRONMENTAL_TIMED[effect_id] then
            if BossArena.apply_effect(effect_id, instance) then applied[#applied + 1] = effect_id end
        elseif Schema.ENVIRONMENTAL_IMMEDIATE[effect_id]
            and (effect_id ~= "spawn_adds" or arena.bounds_authored) then
            BossArena.trigger_arena_effect(arena.id, effect_id, params[effect_id])
        end
    end
    if #applied == 0 then return end
    instance.interruptible = true

    local function remove(active)
        if BossArena.get_active_arena() == arena then
            for _, effect_id in ipairs(applied) do
                BossArena.remove_effect(effect_id, active)
            end
        end
        active:on_cancel(nil)
    end
    instance:on_cancel(remove)
    instance:after(tonumber(env.duration) or pattern.duration or C.Defaults.attack_duration or 1, remove)
end

return M
