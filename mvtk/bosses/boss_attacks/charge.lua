--- Boss charge attack executor.
--
-- Charges are advanced from the boss ATTACKING state one frame at a time.
-- Keeping the movement here (instead of teleporting or using go.animate)
-- lets the hit test sweep every travelled segment, prevents tunnelling at
-- high speed, and gives a jumping player a real way to clear the lane.
-- @module boss_attacks.charge

local C = require "mvtk.bosses.boss_attacks.common"
local AttackScale = require "mvtk.bosses.attack_scale"
local IndicatorGeometry = require "mvtk.bosses.indicator_geometry"
local Indicator = require "mvtk.bosses.boss_indicator"
local Locomotion = require "mvtk.bosses.boss_locomotion"
local Clock = require "mvtk.bosses.boss_clock"
local BossArena = C.Util.require_module("mvtk.bosses.boss_arena")

local M = {}

local EPSILON = 0.001
local advance

local function phase_speed_multiplier(boss)
    return tonumber(boss and boss.speed_multiplier)
        or tonumber(boss and boss.boss_data and boss.boss_data.speed_multiplier)
        or 1.0
end

local function horizontal_facing(boss, boss_pos, player_pos)
    if player_pos and math.abs((player_pos.x or 0) - (boss_pos.x or 0)) > EPSILON then
        return player_pos.x >= boss_pos.x and 1 or -1
    end
    return (boss.facing or 1) >= 0 and 1 or -1
end

local function charge_hits_player(ctx, from_pos, to_pos, body)
    if not body then return false end

    local half_width = ctx.hitbox_half_width + body.half_w
    local min_x = math.min(from_pos.x, to_pos.x) - half_width
    local max_x = math.max(from_pos.x, to_pos.x) + half_width
    local in_swept_x = body.x >= min_x and body.x <= max_x
    -- Sprite players keep the authored root clearance. A separately animated
    -- collider can enter or leave the danger lane without moving the root.
    local height = body.animated and ctx.hitbox_half_height + body.half_h or ctx.hitbox_half_height
    local y = body.animated and body.y or (body.root_y or body.y)
    local in_ground_lane = math.abs(y - ctx.ground_y) <= height
    return in_swept_x and in_ground_lane
end

local function overlaps(body, ctx, from_pos, to_pos)
    if not charge_hits_player(ctx, from_pos, to_pos, body) then return false end
    local half_width = ctx.hitbox_half_width + body.half_w
    local distance = ctx.facing * (body.x - from_pos.x)
    local starts = ctx.hit_schedule.first
    if ctx.speed <= 0 then return true end
    return true, starts + math.max(0, (distance - half_width) / ctx.speed),
        starts + (distance + half_width) / ctx.speed
end

local function damage_player(boss, ctx, count)
    local payload = C.build_payload(
        boss,
        ctx.pattern,
        ctx.damage,
        ctx.facing * ctx.knockback,
        ctx.knockback_y
    )
    for _ = 1, count do C.post_damage(payload) end
    C.print(string.format("[BOSS_ATTACKS] Charge hit player for %d damage", ctx.damage))
end

local function show_danger(ctx, position)
    local width = ctx.hitbox_half_width * 2
    local body = C.Detection.get_player_body()
    local y, height = IndicatorGeometry.charge_band(ctx.ground_y, ctx.hitbox_half_height, body)
    local center = vmath.vector3(position.x, y, position.z + 0.05)
    if not ctx.effect then
        ctx.effect = C.active_box(ctx.instance, center, width, height)
    elseif go.exists(ctx.effect) then
        go.set_position(center, ctx.effect)
        if height ~= ctx.effect_height then
            Indicator.resize_box(msg.url(nil, ctx.effect, "sprite"), width, height)
        end
    end
    ctx.effect_height = height
end

local function hide_danger(ctx)
    C.retire_effect(ctx.instance, ctx.effect)
    ctx.effect, ctx.effect_height = nil, nil
end

local function release_walk(boss, ctx)
    if ctx.grounded_charge then Locomotion.stop_owned_walk(boss) end
end

local function travel(boss, ctx, from, dt)
    local step = math.min(ctx.remaining, ctx.speed * dt)
    if ctx.grounded_charge then
        if not Locomotion.is_grounded(boss) then return from, 0, dt, true end
        local paid = Locomotion.walk_owned(boss, ctx.facing * ctx.speed,
            dt, ctx.target_x, ctx.remaining / ctx.speed)
        if dt > 0 and paid == 0 then return end -- Terrain work carries its time to the next draw.
        local to = go.get_position()
        step = math.min(ctx.remaining, ctx.speed * paid)
        local distance = math.max(0, ctx.facing * (to.x - from.x))
        local blocked = not Locomotion.is_grounded(boss) or distance < step - EPSILON
        return to, blocked and distance or step, math.max(dt, paid), blocked
    end
    local to = vmath.vector3(from.x + ctx.facing * step, ctx.ground_y, from.z)
    go.set_position(to)
    return to, step, dt, false
end

--- Arm a charge. Movement begins when update() is called by the attacking state.
function M.execute(boss, pattern, instance)
    instance = C.instance(boss, pattern, instance)
    C.print("[BOSS_ATTACKS] Charge attack")
    C.supersede_motion(boss)

    local pos = go.get_position()
    local player_pos = C.Detection.get_player_position()
    local facing = boss._attack_facing_locked
        and ((boss._attack_facing_locked >= 0) and 1 or -1)
        or horizontal_facing(boss, pos, player_pos)
    local dash_distance = AttackScale.charge_distance(pattern)
    local base_speed = math.max(1, tonumber(pattern.dash_speed) or C.Defaults.chase_speed or 300)
    local dash_speed = base_speed * phase_speed_multiplier(boss)
    local arena = BossArena and BossArena.get_active_arena and BossArena.get_active_arena()
    local target_x = IndicatorGeometry.charge_target(pos.x, pos.x + facing * dash_distance, pattern, arena, EPSILON, boss)
    local actual_distance = math.abs(target_x - pos.x)
    local half_width, half_height = IndicatorGeometry.charge_extents(pattern, C.Defaults)

    boss.facing = facing
    boss._active_charge = {
        instance = instance,
        pattern = pattern,
        facing = facing,
        speed = dash_speed,
        ground_y = pos.y,
        target_x = target_x,
        remaining = actual_distance,
        travelled = 0,
        hit_schedule = {},
        grounded_charge = Locomotion.active(boss),
        damage = (pattern.damage or C.Defaults.default_melee_damage) * C.damage_mult(boss),
        knockback = pattern.knockback or C.Defaults.default_melee_knockback_x,
        knockback_y = pattern.knockback_y or C.Defaults.default_melee_knockback_y,
        -- The horizontal extent prevents a fast charge from tunnelling through
        -- the player's hurtbox. The vertical extent is intentionally low: get
        -- above this lane and the cactus passes safely underneath.
        hitbox_half_width = half_width,
        hitbox_half_height = half_height,
        recovery_remaining = math.max(0, tonumber(pattern.recovery) or 0),
        complete = actual_distance <= EPSILON,
        finished = actual_distance <= EPSILON and (tonumber(pattern.recovery) or 0) <= 0,
    }

    C.print(string.format(
        "[BOSS_ATTACKS] Charge armed: direction=%d distance=%.0f speed=%.0f",
        facing, actual_distance, dash_speed))

    local charge = boss._active_charge
    charge.release = function()
        hide_danger(charge)
        release_walk(boss, charge)
    end
    instance:on_cancel(function()
        charge.effect, charge.effect_height = nil, nil -- The instance already deleted its objects.
        if boss._active_charge == charge then
            release_walk(boss, charge)
            boss._active_charge = nil
        end
    end)
    charge.duration = (dash_speed > 0 and actual_distance / dash_speed or 0) + charge.recovery_remaining
    instance:each_motion(function(active_instance, dt, now, _, started_at)
        local active = advance(boss, charge, dt, now, started_at)
        -- A finished charge suppresses contact damage until the authored
        -- ATTACKING duration ends, as it did before instance-driven motion.
        local sm = boss.state_machine
        if not active then
            if boss._active_charge ~= charge then
                instance:on_cancel(nil)
            elseif not (sm and sm:get_state() == "attacking") then
                boss._active_charge = nil
                instance:on_cancel(nil)
            end
        end
        if not active then return active_instance:motion_arrival(charge.duration) end
    end)
    return charge
end

--- Advance an armed charge and test its swept hitbox.
-- @return true while travel/recovery is still active, false when complete.
advance = function(boss, ctx, dt, now, started_at)
    if not ctx then return false end
    if ctx.finished then return false end

    dt = math.max(0, tonumber(dt) or 0)
    local recovery_dt = dt

    if not ctx.complete then
        local from_pos = go.get_position()
        local to_pos, step, paid, blocked = travel(boss, ctx, from_pos, dt)
        if not to_pos then return true end
        ctx.ground_y = to_pos.y
        ctx.remaining = math.max(0, ctx.remaining - step)
        ctx.travelled = ctx.travelled + step

        local travel_dt = ctx.speed > 0 and step / ctx.speed or 0
        -- A charge stopped before this sweep has no active area to show.
        if not blocked or step > 0 then
            local schedule = ctx.hit_schedule
            schedule.first = math.max(started_at, now - paid)
            schedule.through = schedule.first + travel_dt
            ctx.instance._hit_schedule = schedule
            local body, count = C.hit_body(ctx.instance, overlaps, "charge", ctx, from_pos, to_pos)
            ctx.instance._hit_schedule = nil
            if body then damage_player(boss, ctx, count) end
        end

        recovery_dt = math.max(0, paid - travel_dt)
        if blocked or Clock.reached(0, ctx.remaining) then
            ctx.complete = true
            hide_danger(ctx)
            release_walk(boss, ctx)
            -- Land exactly on the clamped target even after small float drift.
            if blocked then
                ctx.duration = ctx.travelled / ctx.speed + ctx.recovery_remaining
            else
                go.set_position(vmath.vector3(ctx.target_x, ctx.ground_y, to_pos.z))
            end
            C.print(string.format(
                "[BOSS_ATTACKS] Charge travel complete: distance=%.0f",
                ctx.travelled))
        else
            show_danger(ctx, to_pos)
        end
    end

    if ctx.complete then
        ctx.recovery_remaining = math.max(0, ctx.recovery_remaining - recovery_dt)
        ctx.finished = Clock.reached(0, ctx.recovery_remaining)
    end

    return not ctx.finished
end

-- Pure helper exposed for focused geometry tests.
M._charge_hits_player = charge_hits_player

return M
