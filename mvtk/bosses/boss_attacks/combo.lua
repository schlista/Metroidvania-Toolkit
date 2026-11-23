--- Boss combo attack executor.
-- Schedules sub-patterns by delay and re-enters the dispatcher via
-- C.execute_pattern so each combo step uses the same code path as the
-- standalone version of that attack.
-- @module boss_attacks.combo

local C = require "mvtk.bosses.boss_attacks.common"
local Schema = require "mvtk.bosses.attack_pattern_schema"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    local ok, err = Schema.validate(pattern, pattern._attack_name or "combo")
    if not ok then
        C.print("[BOSS_ATTACKS] " .. err)
        return
    end
    local steps = pattern.combo or {}
    C.print(string.format("[BOSS_ATTACKS] Combo attack with %d steps", #steps))

    for index, step in ipairs(steps) do
        local delay = tonumber(step.delay) or 0
        local repetitions = step["repeat"]
        if repetitions then
            -- Repeated swings are a foreground sequence, even as a child
            -- of an authored persistent attack.
            instance.persist, instance.interruptible = false, true
        end
        local function execute_step()
            local step_pattern = nil
            if type(step.pattern) == "string" and boss.get_attack_pattern then
                local entry
                if step.special ~= nil or step.hazard ~= nil then entry = {_legacy_combo_step = step} end
                step_pattern = boss:get_attack_pattern(step.pattern, entry)
            elseif type(step) == "table" and step.type then
                step_pattern = step
            end

            if not step_pattern then
                C.print(string.format("[BOSS_ATTACKS] Combo step missing pattern: %s",
                    tostring(step.pattern)))
                return
            end

            local merged = step_pattern._combo_step_applied and step_pattern or C.merge_step_pattern(step_pattern, step)
            if not merged._combo_step_applied and (merged.type == "special" or merged.type == "hazard") then
                merged._attack_name = merged._attack_name or ("%s step %d"):format(pattern._attack_name or "combo", index)
                local resolved, err = Schema.resolve(merged, C.Defaults, print)
                if not resolved then print("[BOSS_ATTACKS] " .. err); return end
            end
            if step.aim == "player" and boss.face_player then boss:face_player() end
            C.execute_pattern(boss, merged, {play_animation = true, instance = instance:child(merged),
                warn = merged._legacy_cast or merged.warn_in_combo})
        end
        for repetition = 1, repetitions or 1 do
            instance:after(delay * repetition, execute_step)
        end
    end
end

return M
