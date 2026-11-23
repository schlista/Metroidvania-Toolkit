--- Boss grab attack executor.
-- On hit: applies an initial damage payload, holds the boss in a "grab_hold"
-- loop for `duration`, then fires the "grab_throw" animation and applies
-- knockback. No-op on miss.
-- @module boss_attacks.grab

local C = require "mvtk.bosses.boss_attacks.common"
local Indicator = require "mvtk.bosses.indicator_geometry"

local M = {}

function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    C.print("[BOSS_ATTACKS] Grab attack")

    local grab = pattern.grab or {}
    local pos = go.get_position()
    local reach, width, height = Indicator.grab_box(pattern, C.Defaults)
    local damage = (grab.damage or pattern.damage or C.Defaults.default_grab_damage) * C.damage_mult(boss)
    local duration = grab.duration
        or (boss.boss_data and boss.boss_data.grab_duration)
        or C.Defaults.default_grab_duration
    local throw_kb = grab.throw_knockback
        or (boss.boss_data and boss.boss_data.grab_throw_knockback)
        or C.Defaults.default_grab_throw_kb
    local throw_ky = grab.throw_knockback_y or C.Defaults.default_melee_knockback_y

    local hitbox_pos = vmath.vector3(pos.x + reach * 0.5 * boss.facing, pos.y, pos.z)
    local function overlaps(body)
        return C.Geometry.rect_in_box(hitbox_pos, width, height, body)
    end

    -- The grab starts at execution, including when dispatched by a combo.
    if not C.hit_body(instance, overlaps, "box", hitbox_pos, width, height) then return end
    local initial_payload = C.build_payload(boss, pattern, damage, 0, 0)
    initial_payload.grab_start = true
    initial_payload.grab_duration = duration
    C.post_damage(initial_payload)

    C.play_resolved_animation(boss, "grab_hold", true)

    instance:after(duration, function()
        C.play_resolved_animation(boss, "grab_throw", true)
        local throw_payload = C.build_payload(
            boss, pattern, 0,
            throw_kb * boss.facing, throw_ky
        )
        throw_payload.grab_release = true
        C.post_damage(throw_payload)
        C.print(string.format("[BOSS_ATTACKS] Grab released with %d knockback", throw_kb))
    end)
end

return M
