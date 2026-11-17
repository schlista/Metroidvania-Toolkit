-- Pure room/world-space footprint shared by validation and the live blocker.
local M = {}

function M.swept_box(h, blade_w, blade_h, arc_degrees)
    h, blade_w = math.max(0, tonumber(h) or 0), math.max(0, tonumber(blade_w) or 0)
    local arc = math.abs(tonumber(arc_degrees) or 70)
    if arc > 180 then
        local diameter = 2 * h + blade_w
        return 0, 0, diameter, diameter
    end
    return 0, -h / 2, 2 * h * math.sin(math.rad(arc / 2)) + blade_w, h
end

-- Blade angle after `elapsed` seconds of unpaused swing. Matches the engine's
-- go.animate PLAYBACK_LOOP_PINGPONG with EASING_INOUTSINE: one full there-and-back
-- cycle takes swing_seconds (comp_anim.cpp doubles t for ping-pong), after start_delay.
function M.swing_angle(arc_degrees, from_right, swing_seconds, start_delay, elapsed)
    local start = math.abs(tonumber(arc_degrees) or 70) / 2 * (from_right and 1 or -1)
    local t = (tonumber(elapsed) or 0) - math.max(0, tonumber(start_delay) or 0)
    if t <= 0 then return start end
    local period = math.max(0.001, tonumber(swing_seconds) or 1.2)
    local u = (t % period) / period * 2
    if u > 1 then u = 2 - u end
    return start - 2 * start * (1 - math.cos(math.pi * u)) / 2
end

return M
