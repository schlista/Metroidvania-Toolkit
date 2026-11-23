-- Sample shot origins in the two lanes left after reserving the warned gap.
local C = require "mvtk.bosses.boss_attacks.common"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local Feedback = C.Util.require_module("mvtk.combat.combat_feedback")

local M = {}

function M.execute(boss, pattern, instance)
    local settings = C.stationary_options(pattern)
    if not settings then return end
    instance = C.stationary_instance(boss, pattern, instance)
    local cue = Telegraph.take_stationary(boss, pattern, settings)
    Telegraph.cancel(cue)
    local rect = cue.rect
    if not rect then return end
    if settings.shake and Feedback and Feedback.screen_shake then
        Feedback.screen_shake(nil, settings.shake)
    end

    local fire = C.stationary_shots(boss, pattern, instance, settings)
    local left_width = cue.gap_left - rect.min_x
    local right_width = rect.max_x - cue.gap_right
    local left_count = math.floor(settings.count * left_width / (left_width + right_width) + 0.5)
    for index = 1, settings.count do
        local x
        if index <= left_count then
            x = rect.min_x + (index - 0.5) * left_width / left_count
        else
            x = cue.gap_right + (index - left_count - 0.5) * right_width / (settings.count - left_count)
        end
        local function drop()
            fire(vmath.vector3(x, rect.max_y, cue.origin.z), -math.pi * 0.5)
        end
        local delay = (index - 1) * settings.stagger
        if delay > 0 then instance:after(delay, drop) else drop() end
    end
end

return M
