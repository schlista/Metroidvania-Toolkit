-- One shrink, relocation and regrowth sequence for attack and idle blinks.
local Motion = require "mvtk.bosses.boss_motion"
local Invulnerability = require "mvtk.combat.invulnerability"
local Clock = require "mvtk.bosses.boss_clock"
local Defaults = require("mvtk.core.util").require_config("developer.config.boss_defaults", {})
local Cues = require("mvtk.bosses.transition_cues").resolve(Defaults)
local M = {}

function M.start(boss, relocate)
    local url = boss.self_url
    local from = go.get_scale(url)
    local base = boss._base_scale or Motion.get_base_scale(url)
    local small = Motion.disappear_scale(base)
    local shrink = math.max(0, Cues.teleport.shrink_duration)
    local grow = math.max(0, Cues.teleport.grow_duration)
    local release = Invulnerability.start(boss.boss_data or boss, math.huge, "reposition", true)
    local elapsed, moved = 0, false

    local function cancel()
        Motion.set_scale_at(url, small, base, 1)
        if release then release() end
    end

    local function advance(dt)
        elapsed = elapsed + dt
        if not Clock.reached(elapsed, shrink) then
            Motion.set_scale_at(url, from, small, elapsed / shrink, "in_cubic")
            return false
        end
        if not moved then
            moved = true
            Motion.set_scale_at(url, from, small, 1)
            relocate()
        end
        local progress = Clock.reached(elapsed, shrink + grow) and 1
            or math.max(0, (elapsed - shrink) / grow)
        Motion.set_scale_at(url, small, base, progress, "out_cubic")
        if progress == 1 then
            if release then release() end
            return true
        end
        return false
    end

    return advance, cancel, shrink + grow
end

return M
