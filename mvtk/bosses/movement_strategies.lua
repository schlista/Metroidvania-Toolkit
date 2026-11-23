-- mvtk/bosses/movement_strategies.lua
-- ============================================================================
-- Boss Movement Strategies
-- ============================================================================
-- Dispatches per-phase movement behavior when the boss is in its IDLE state
-- (i.e. between attacks). Each strategy picks the animation key and updates
-- the boss position for that frame.
--
-- Strategies are selected by a phase's `movement_profile` field:
--   "ground_chase" | "hover" | "jump_attack" | "teleport" | "stationary" |
--   "wall_crawl" | "burrow" | "flying_patrol"
-- Every value of Tiled's `movement_profiles` enum needs an entry here
-- (test/boss_movement_profile_tests.lua); an unknown name logs once and falls
-- back to ground_chase.
--
-- To add a custom strategy:
--   1. Add a function to M.strategies below.
--   2. Expose its id in developer/config/ (or just name it and author the
--      phase in Tiled with movement_profile = <that_id>).
-- ============================================================================

local Util = require "mvtk.core.util"
local Detection = require "mvtk.enemies.detection"
local BossAnimations = Util.require_module("mvtk.bosses.boss_animations")
local Locomotion = require "mvtk.bosses.boss_locomotion"
local Confinement = require "mvtk.bosses.boss_confinement"
local Blink = require "mvtk.bosses.boss_blink"
local Invulnerability = require "mvtk.combat.invulnerability"
local Telegraph = require "mvtk.bosses.boss_telegraph"
local Clock = require "mvtk.bosses.boss_clock"
local Defaults = Util.require_config("developer.config.boss_defaults", {})

local M = {}
local DEFAULT_TELEPORT_ANCHORS = {"near_player", "far_from_player"}

local function anim(boss, key)
    if BossAnimations and BossAnimations.resolve then
        return BossAnimations.resolve(boss, key)
    end
    return key
end

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

local function play(boss, key, loop)
    if boss and boss.play_animation then
        boss:play_animation(anim(boss, key), loop ~= false)
    end
end

local function distance_to_player(boss)
    local player_pos = Detection.get_player_position()
    local boss_pos = boss:get_position()
    if not (player_pos and boss_pos) then
        return math.huge, nil, nil
    end
    return vmath.length(player_pos - boss_pos), player_pos, boss_pos
end

local function speed_for_phase(boss, base_speed)
    local mult = (boss.boss_data and boss.boss_data.speed_multiplier) or 1.0
    return (base_speed or 120) * mult
end

local function leashed_x(ctx, x)
    if ctx.leash_left then return math.max(ctx.leash_left, math.min(ctx.leash_right, x)) end
    return x
end

local function move_to_anchor(boss, position, target, speed, dt, max_travel, ctx)
    if dt <= 0 then return false end
    if ctx and ctx.leash_left then target.x = leashed_x(ctx, target.x) end
    local distance = vmath.length(target - position)
    local travel = math.min(distance, max_travel or distance)
    return boss:move_toward(target, math.min(speed, travel / dt), dt) ~= false
end

local function walk_to(boss, target, pos, speed, travel, dt)
    local dx = target - pos.x
    if dt <= 0 or dx == 0 then return false end
    local vx = math.min(speed, math.abs(dx) / dt, travel / dt)
    if vx <= 0 then return false end
    Locomotion.walk(boss, dx < 0 and -vx or vx)
    return true
end

local function ground_chase(boss, ctx, dt, clip)
    local distance, player_pos, boss_pos = M.attack_distance(boss, ctx)
    if player_pos and boss_pos and distance > ctx.attack_range and distance >= ctx.min_chase_distance then
        local speed = speed_for_phase(boss, ctx.chase_speed)
        local travel = distance - ctx.attack_range
        local moved
        if Locomotion.active(boss) then
            moved = walk_to(boss, leashed_x(ctx, player_pos.x), boss_pos, speed, travel, dt)
            if moved then
                local state = boss._locomotion
                state.walk_clip = clip
                return state.walk_blocked and "idle" or "moving"
            end
        else
            local target = vmath.vector3(player_pos.x, boss_pos.y, boss_pos.z)
            moved = move_to_anchor(boss, boss_pos, target, speed, dt, travel, ctx)
        end
        if moved then
            play(boss, clip, true)
            return "moving"
        end
    end
    if boss.current_animation == anim(boss, clip) then play(boss, "idle", true) end
    return "idle"
end

-- Project the three-dimensional stop radius onto the axes a profile can move.
local function radius_on_path(radius, dy, dz)
    return math.sqrt(math.max(0, radius ^ 2 - dy ^ 2 - dz ^ 2))
end

-- ----------------------------------------------------------------------------
-- Strategies
-- ----------------------------------------------------------------------------

M.strategies = {}

--- ground_chase: default. Walk/run toward player; idle when in range.
function M.strategies.ground_chase(boss, ctx, dt)
    return ground_chase(boss, ctx, dt, "walk")
end

--- Hover beside the player, holding the approach side through a crossing.
function M.strategies.hover(boss, ctx, dt)
    local _, player_pos, boss_pos = distance_to_player(boss)
    if player_pos and boss_pos then
        local range = math.max(0, ctx.attack_range)
        local dx = boss_pos.x - player_pos.x
        local side = boss._hover_phase == ctx.phase and boss._hover_side
        if not side or dx * side < -range then
            side = dx == 0 and -(boss.facing or 1) or (dx < 0 and -1 or 1)
        end
        local target_x = leashed_x(ctx, player_pos.x + side * range)
        if range > 0 and (boss._confine_rect or ctx.leash_left) then
            local fitted_x = Confinement.clamp_boss(boss, target_x, boss_pos.y)
            if (fitted_x - player_pos.x) * side <= 0 then
                local opposite = leashed_x(ctx, player_pos.x - side * range)
                local opposite_x = Confinement.clamp_boss(boss, opposite, boss_pos.y)
                if (opposite_x - player_pos.x) * side < 0 then
                    side, target_x = -side, opposite
                end
            end
        end
        boss._hover_phase, boss._hover_side = ctx.phase, side
        local target = vmath.vector3(target_x, boss_pos.y, boss_pos.z)
        -- Maintain hover height relative to the boss's anchor row. If the
        -- phase declared hover_height, nudge vertically toward it.
        if ctx.hover_height and ctx.hover_height > 0 then
            local anchor_y = (boss.boss_data and boss.boss_data.spawn_y) or boss_pos.y
            target.y = anchor_y + ctx.hover_height
        end
        if (target.x ~= boss_pos.x or target.y ~= boss_pos.y)
            and move_to_anchor(boss, boss_pos, target, speed_for_phase(boss, ctx.chase_speed), dt) then
            play(boss, "hover_move", true)
            return "moving"
        end
    else
        boss._hover_phase, boss._hover_side = nil, nil
    end

    play(boss, "hover_idle", true)
    return "idle"
end

--- jump_attack: stay in place until in range; then jump toward player.
function M.strategies.jump_attack(boss, ctx, dt)
    local dist, player_pos, boss_pos = distance_to_player(boss)
    local jump_speed = ctx.jump_speed and ctx.jump_speed > 0 and ctx.jump_speed
        or speed_for_phase(boss, ctx.chase_speed)

    if Locomotion.active(boss) then
        local state = boss._locomotion
        if not Locomotion.is_grounded(boss) then
            state.stop_x = state.jump_stop_x
            play(boss, "jump_air", true)
            return "moving"
        end
        if dt <= 0 or ctx.decision == false then return "idle" end
        if (state.jump_recovery or 0) <= 0 and player_pos and dist > ctx.attack_range then
            local dx = player_pos.x - boss_pos.x
            local stop = radius_on_path(ctx.attack_range, boss_pos.y - player_pos.y, boss_pos.z - player_pos.z)
            local dir = dx < 0 and -1 or 1
            local target_x = leashed_x(ctx, player_pos.x - dir * math.min(stop, math.abs(dx)))
            if (target_x - boss_pos.x) * dir > 0 then
                local height = ctx.jump_height > 0 and ctx.jump_height or math.max(0, tonumber(Defaults.jump_height) or 96)
                local vx, vy = jump_speed * dir, math.sqrt(2 * Locomotion.gravity() * height)
                local landing = Locomotion.plan_jump(boss, boss_pos, target_x, vx, vy)
                if landing and Locomotion.jump(boss, vx, vy) then
                    state.jump_stop_x, state.stop_x = landing, landing
                    play(boss, "jump_air", true)
                    return "moving"
                end
            else
                Locomotion.clear_jump_plan(boss)
            end
        else
            Locomotion.clear_jump_plan(boss)
        end
        play(boss, "idle", true)
        return "idle"
    end

    -- Only commit to a jump if the player is outside attack range.
    if player_pos and dist > ctx.attack_range then
        -- Boss hops toward the player at jump_speed; visual arc is up to the
        -- animation. Position still lerps linearly.
        local dz = boss_pos.z - player_pos.z
        local travel = math.max(0, radius_on_path(dist, 0, dz) - radius_on_path(ctx.attack_range, 0, dz))
        local target = ctx.leash_left and vmath.vector3(player_pos) or player_pos
        if move_to_anchor(boss, boss_pos, target, jump_speed, dt, travel, ctx) then
            play(boss, "jump_air", true)
            return "moving"
        end
    end

    play(boss, "idle", true)
    return "idle"
end

local function blink_target(boss, ctx, name, pos, player, body)
    local rect = boss._confine_rect or Confinement.resolve_rect(boss.config)
    local hw, hh, feet = Confinement.half_extents(boss.config, boss)
    local target = Confinement.anchor(rect, name, pos, player, hw, hh, feet)
    if not target then return end
    local body_x = body and body.x or player and player.x
    local separation = boss._body.half_width + (body and body.half_w or 0)
    local side
    if player and (name == "near_player" or name == "behind_player") then
        side = player.x >= pos.x and -1 or 1
        if name == "behind_player" then side = -side end
        local chase_x = player.x + side * math.max(ctx.attack_range, ctx.min_chase_distance)
        local safe_x = body_x + side * separation
        target.x = side > 0 and math.max(chase_x, safe_x) or math.min(chase_x, safe_x)
    end
    target.x = Confinement.clamp(leashed_x(ctx, target.x), target.y, rect, hw, hh, feet)
    if body_x and (side and (target.x - body_x) * side or math.abs(target.x - body_x)) < separation then
        return
    end
    return target, rect, hh, feet
end

local function begin_blink(boss, ctx)
    local pos = boss:get_position()
    local body = Detection.get_player_body()
    local player = body and {x = Telegraph.body_target(body)} or Detection.get_player_position()
    local names = ctx.teleport_anchors
    if type(names) ~= "table" or #names == 0 then names = Defaults.teleport_anchors end
    if type(names) ~= "table" or #names == 0 then names = DEFAULT_TELEPORT_ANCHORS end
    local state = boss._locomotion
    state.anchors_left = state.anchors_left or #names
    local body_width = 2 * boss._body.half_width
    while state.anchors_left > 0 do
        local index = state.next_anchor or 1
        local target, rect, hh, feet = blink_target(boss, ctx, names[index], pos, player, body)
        if target and not Locomotion.can_probe(boss, 2) then return end
        state.next_anchor = index % #names + 1
        state.anchors_left = state.anchors_left - 1
        if target then
            local y = Locomotion.landing(boss, target, hh)
            local _, confined_y
            if y then _, confined_y = Confinement.clamp(target.x, y, rect, 0, hh, feet) end
            if y and confined_y == y then
                target.y = y
                local dx, dy = target.x - pos.x, target.y - pos.y
                if dx * dx + dy * dy > body_width * body_width then
                    local marker = Telegraph.mark_blink_destination(boss, target, body_width)
                    local advance, cancel = Blink.start(boss, function()
                        Locomotion.land_at(boss, target)
                    end)
                    state.blink_advance = function(dt)
                        if advance(dt) then
                            Telegraph.cancel(marker)
                            return true
                        end
                    end
                    state.blink_cancel = function()
                        cancel()
                        Telegraph.cancel(marker)
                    end
                    break
                end
            end
        end
    end
    state.teleport_elapsed, state.anchors_left = 0, nil
end

--- teleport: opts in to timing and a floor-settled relocation.
function M.strategies.teleport(boss, ctx, dt)
    if ctx.decision ~= false and Locomotion.active(boss) and dt > 0 and not boss._active_charge then
        local state = boss._locomotion
        if not state.blink_advance and Clock.reached(state.teleport_elapsed, ctx.teleport_interval) then
            begin_blink(boss, ctx)
        end
    end
    play(boss, "idle", true)
    return "idle"
end

--- stationary: does not move. Faces the player unless facing_lock is set.
function M.strategies.stationary(boss, ctx, _dt)
    if ctx.decision ~= false and ctx.facing_lock ~= true and boss.face_player then
        boss:face_player()
    end
    play(boss, "idle", true)
    return "idle"
end

--- flying_patrol: the airborne profile name shared with enemies, which map it
--- to hover too (mvtk/enemies/enemy_overrides.lua).
M.strategies.flying_patrol = M.strategies.hover

--- burrow: travels along the ground toward the player like ground_chase,
--- playing the burrow clips (boss_animations.lua falls back to move/idle when
--- a boss has no burrow art).
local function release_burrow(boss, state)
    if state.burrow_release then state.burrow_release() end
    if state.emerge_cue then Telegraph.cancel(state.emerge_cue) end
    state.burrow_release, state.emerge_cue, state.burrow_warning = nil, nil, nil
    boss.boss_data._burrowing = nil
end

local function emerge(boss, state)
    if state.burrow_warning then return end
    state.burrow_warning = math.max(0, tonumber(Defaults.burrow_warning_time) or 0.25)
    if state.burrow_warning == 0 then
        release_burrow(boss, state)
    else
        play(boss, "burrow_out", false)
        local width = boss._body.half_width * 2
        state.emerge_cue = Telegraph.begin(boss, {
            type = "burrow_emerge", telegraph_shape = "circle", telegraph_size = {x = width, y = width},
        }, state.burrow_warning, true)
    end
end

function M.strategies.burrow(boss, ctx, dt)
    if not Locomotion.active(boss) then return ground_chase(boss, ctx, dt, "burrow_idle") end
    local state = boss._locomotion
    if state.burrow_warning then
        state.burrow_warning = state.burrow_warning - dt
        if Clock.reached(Clock.window_lead(dt), state.burrow_warning) then
            release_burrow(boss, state)
            play(boss, "idle", true)
        end
        return "idle"
    end
    local result = ground_chase(boss, ctx, dt, "burrow_idle")
    if boss.boss_data._burrowing and not state.walk_clip and dt > 0 then emerge(boss, state) end
    return result
end

--- wall_crawl: moves horizontally along the ceiling / wall plane; uses
--- crawl animations. Vertical position is held at the spawn anchor.
function M.strategies.wall_crawl(boss, ctx, dt)
    local dist, player_pos, boss_pos = distance_to_player(boss)

    if player_pos and boss_pos and dist > ctx.attack_range then
        local anchor_y = (boss.boss_data and boss.boss_data.spawn_y) or boss_pos.y
        -- Intersect the stop radius with the crawl row. If the row is too
        -- high or low to enter the radius, approach its nearest point.
        local dy = anchor_y - player_pos.y
        local dz = boss_pos.z - player_pos.z
        local dx = boss_pos.x - player_pos.x
        local stop_x = radius_on_path(ctx.attack_range, dy, dz)
        local target_x = player_pos.x + (dx < 0 and -1 or 1) * math.min(math.abs(dx), stop_x)
        local target = vmath.vector3(target_x, anchor_y, boss_pos.z)
        if move_to_anchor(boss, boss_pos, target, speed_for_phase(boss, ctx.chase_speed), dt, nil, ctx) then
            play(boss, "crawl_move", true)
            return "moving"
        end
    end

    play(boss, "crawl_idle", true)
    return "idle"
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

--- Resolve the strategy function for a profile name. Falls back to
--- ground_chase when the profile is missing or invalid.
function M.get(profile)
    if type(profile) == "string" and profile ~= "" and M.strategies[profile] then
        return M.strategies[profile]
    end
    return M.strategies.ground_chase
end

--- Resolve the actual movement profile, including the same ground-chase
--- fallback used by get().
local warned_profiles = {}

function M.resolve_profile(boss, phase)
    phase = phase or {}
    local cfg = (boss and boss.config) or {}
    local profile = phase.movement_profile or cfg.movement_profile or "ground_chase"
    if type(profile) ~= "string" or profile == "" or not M.strategies[profile] then
        local name = tostring(profile)
        if profile ~= nil and profile ~= "" and not warned_profiles[name] then
            warned_profiles[name] = true
            print("[BOSS] WARNING: unknown movement_profile '" .. name .. "'; using ground_chase")
        end
        return "ground_chase"
    end
    return profile
end

-- These profiles approach a horizontal attack range from their own height.
local HORIZONTAL_RANGE = { ground_chase = true, burrow = true, hover = true, flying_patrol = true }

--- Distance used by movement stopping and attack gating.
function M.attack_distance(boss, phase)
    local euclidean, player_pos, boss_pos = distance_to_player(boss)
    if player_pos and boss_pos and HORIZONTAL_RANGE[M.resolve_profile(boss, phase)] then
        return math.abs(player_pos.x - boss_pos.x), player_pos, boss_pos
    end
    return euclidean, player_pos, boss_pos
end

-- Run the active profile's strategy for one frame.
--   boss     — boss runtime instance (self in boss.script)
--   phase    — current phase table (may be nil; falls back to defaults)
--   defaults — numeric defaults {chase_speed, attack_range, min_chase_distance}
--   dt       — delta time
--   approach — resolved chase stop for this phase, when a moveset is available
-- Returns "moving" or "idle" (for bookkeeping in callers).
function M.run(boss, phase, defaults, dt, approach, decision)
    phase = phase or {}
    defaults = defaults or {}
    local cfg = boss.config or {}

    local profile = M.resolve_profile(boss, phase)
    local ctx = {
        chase_speed        = cfg.chase_speed        or defaults.chase_speed        or 120,
        attack_range       = phase.attack_range     or cfg.attack_range            or defaults.attack_range or 150,
        min_chase_distance = cfg.min_chase_distance or defaults.min_chase_distance or 80,
        hover_height       = phase.hover_height       or 0,
        jump_height        = phase.jump_height        or 0,
        jump_speed         = phase.jump_speed         or 0,
        facing_lock        = phase.facing_lock        == true,
        movement_profile   = profile,
        phase              = phase,
        decision           = decision ~= false,
    }
    if profile ~= "hover" and profile ~= "flying_patrol" then
        boss._hover_phase, boss._hover_side = nil, nil
    end
    local leash = tonumber(phase.leash_radius) or 0
    local spawn_x = boss.boss_data and boss.boss_data.spawn_x
    if leash > 0 and spawn_x then ctx.leash_left, ctx.leash_right = spawn_x - leash, spawn_x + leash end
    boss._returning_to_leash = nil
    local state = boss._locomotion
    if state and state.active then
        state.leash_left, state.leash_right = ctx.leash_left, ctx.leash_right
    end
    if ctx.leash_left then
        local pos = boss:get_position()
        local x = leashed_x(ctx, pos.x)
        if x ~= pos.x then
            boss._returning_to_leash = true
            local speed = speed_for_phase(boss, ctx.chase_speed)
            if Locomotion.active(boss) then
                if walk_to(boss, x, pos, speed, math.huge, dt) then state.walk_clip = "walk" end
                return state.walk_blocked and "idle" or "moving"
            end
            local target = vmath.vector3(x, pos.y, pos.z)
            if move_to_anchor(boss, pos, target, speed, dt, nil, ctx) then
                play(boss, "walk", true)
                return "moving"
            end
            return "idle"
        end
    end
    if profile == "teleport" and state and state.active then
        local interval = tonumber(phase.teleport_interval) or 0
        if interval <= 0 then interval = tonumber(cfg.teleport_interval) or 0 end
        ctx.teleport_interval = interval > 0 and interval or math.max(0, tonumber(Defaults.teleport_interval) or 3)
        local anchors = phase.teleport_anchors
        ctx.teleport_anchors = type(anchors) == "table" and #anchors > 0 and anchors or cfg.teleport_anchors
    end
    if approach ~= nil then
        ctx.attack_range = approach
        ctx.min_chase_distance = math.min(ctx.min_chase_distance, approach)
    end

    return M.get(profile)(boss, ctx, dt)
end

function M.prepare_frame(boss, phase, dt)
    Locomotion.begin_frame(boss, dt)
    local profile = M.resolve_profile(boss, phase)
    Locomotion.set_profile(boss, profile)
    local state = boss._locomotion
    if not state then return end
    -- Count fight time during ordinary attacks as well as idle. Only the
    -- idle strategy may spend an elapsed interval on a blink.
    if state.active and profile == "teleport" and not state.blink_advance then
        state.teleport_elapsed = (state.teleport_elapsed or 0) + dt
    end
    state.walk_clip = nil
    local radius = tonumber(phase and phase.leash_radius)
    if radius and radius > 0 then
        local spawn_x = boss.boss_data.spawn_x
        state.leash_left, state.leash_right = spawn_x - radius, spawn_x + radius
    end
    state.stop_x = state.jump_stop_x
end

function M.waiting_to_attack(boss)
    local state = boss._locomotion
    return boss._returning_to_leash or state and (state.blink_advance or state.burrow_warning)
end

function M.may_attack(boss)
    local state = boss._locomotion
    if not state then return true end
    if state.blink_advance or state.burrow_warning then return false end
    if boss.boss_data._burrowing then
        state.walk_clip = nil
        Locomotion.walk(boss, 0)
        emerge(boss, state)
        return not boss.boss_data._burrowing
    end
    return true
end

function M.interrupt(boss, reset_profile)
    local state = boss._locomotion
    if not state then return end
    release_burrow(boss, state)
    if state.blink_cancel then state.blink_cancel() end
    state.blink_advance, state.blink_cancel = nil, nil
    state.walk_clip, state.walk_blocked = nil, nil
    Locomotion.clear_jump_plan(boss)
    if reset_profile then state.teleport_elapsed, state.next_anchor, state.anchors_left = nil, nil, nil end
    state.vx = 0
end

function M.update_locomotion(boss, dt)
    if not Locomotion.active(boss) or dt <= 0 then return end
    local state = boss._locomotion
    if state.blink_advance and not boss._active_charge then
        if state.blink_advance(dt) then state.blink_advance, state.blink_cancel = nil, nil end
        return
    end
    local walk_clip = state.walk_clip
    local old_x = walk_clip and boss:get_position().x
    Locomotion.update(boss, dt)
    local moved = old_x and boss:get_position().x ~= old_x and not boss._active_charge
    if old_x then state.walk_blocked = not moved end
    if moved then
        play(boss, walk_clip, true)
        if walk_clip == "burrow_idle" and not boss.boss_data._burrowing then
            boss.boss_data._burrowing = true
            state.burrow_release = Invulnerability.start(boss.boss_data, math.huge, "burrow", true)
        end
    elseif boss.boss_data._burrowing and not state.burrow_warning then
        emerge(boss, state)
    elseif walk_clip and boss.current_animation == anim(boss, walk_clip) then
        play(boss, "idle", true)
    end
end

return M
