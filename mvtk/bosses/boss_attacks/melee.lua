--- Boss melee attack executor.
-- A swing is a box in front of the boss, tested against the player's body for
-- a short active time, like the other boss attacks.
-- @module boss_attacks.melee

local C = require "mvtk.bosses.boss_attacks.common"
local AttackScale = require "mvtk.bosses.attack_scale"

local M = {}

local function schedule_followups(boss, pattern, instance)
    for _, strike in ipairs(pattern.followup_strikes or {}) do
        local child = C.merge_step_pattern(pattern, strike)
        child.followup_strikes = nil
        instance:after(strike.delay - strike.telegraph_time, function()
            C.execute_pattern(boss, child, {instance = instance:child(child), warn = true})
        end)
    end
end

function M.execute(boss, pattern, instance)
    instance = C.stationary_instance(boss, pattern, instance)
    C.print("[BOSS_ATTACKS] Executing melee attack")

    local facing = boss.facing or 1
    local pos = go.get_position()
    local offset, half_w, half_h = AttackScale.melee_box(pattern, C.Defaults)
    local center = vmath.vector3(pos.x + offset * facing, pos.y, pos.z)
    local damage = (pattern.damage or C.Defaults.default_melee_damage) * C.damage_mult(boss)
    local knockback_x = pattern.knockback or C.Defaults.default_melee_knockback_x
    local knockback_y = pattern.knockback_y or C.Defaults.default_melee_knockback_y
    local active_time = tonumber(pattern.active_time)
        or tonumber(C.Defaults.default_melee_active_time) or C.DEFAULT_MELEE_ACTIVE_TIME

    local function overlaps(body)
        return C.Geometry.rect_in_box(center, half_w, half_h, body)
    end

    local function check(active)
        local body, count = C.hit_body(active, overlaps, "box", center, half_w, half_h)
        if not body then return end
        local payload = C.build_payload(boss, pattern, damage, knockback_x * facing, knockback_y)
        payload.dir = facing
        -- A swing can be parried only when its pattern opts in, which is also
        -- what gives it a parry tell.
        payload.parryable = pattern.parryable == true
        for _ = 1, count do C.post_damage(payload) end
        C.print(string.format("[BOSS_ATTACKS] Melee hit player for %d damage", damage))
    end

    -- A combo or reposition can start this child during the runtime update.
    -- Sample at launch even if the next frame crosses the entire hit window.
    C.launch_sample(instance, check)
    if active_time > 0 then
        local effect
        if instance:launch_age() < active_time then
            effect = C.active_box(instance, vmath.vector3(center.x, center.y, center.z + 0.05),
                half_w * 2, half_h * 2)
        end
        C.active_frames(instance, active_time, check, false, function()
            C.retire_effect(instance, effect)
        end, true)
    end
    schedule_followups(boss, pattern, instance)
end

return M
