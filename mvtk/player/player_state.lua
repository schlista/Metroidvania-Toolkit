-- mvtk/player/player_state.lua
-- Kinematic movement state using input.move_x and player settings.
--
-- Responsibilities:
-- - Maintain player locomotion velocities and timers (ground/air)
-- - Handle jump (ground/coyote/air), slide, air-dash, wall mechanics
-- - Provide small helpers to request actions from the main player script
--
-- Usage:
--   local PSTATE = require 'mvtk.player.player_state'
--   function init(self)
--     PSTATE.init(self)
--   end
--   function update(self, dt)
--     PSTATE.update(self, input, dt)
--   end
local Util = require "mvtk.core.util"
local RuntimeSettings = require "developer.config.runtime_settings"
local PS = RuntimeSettings.get_player_settings()
local ACTIONS = Util.require_config("developer.config.player_actions")
local CONFIG = Util.require_config("developer.config.resolved_config")
local Debug = Util.require_config("developer.config.debug_config", { global = {}, gameplay = {}, movement = {} })
local SurfaceClassifier = require "mvtk.core.surface_classifier"
local BonePhysics = require "mvtk.player.bone_physics"
-- Cache Audio/FX at module level to avoid pcall(require) on every jump/dash/slide
local Audio = Util.require_module("mvtk.audio.audio")
local FX = Util.require_module("mvtk.fx.fx")
-- Tiny helper that consolidates the per-frame `if (x or 0) > 0 then x =
-- math.max(0, x - dt) end` pattern used dozens of times in this file.
local Timers = require "mvtk.player.timers"
-- Phase 5 step 31: pure jump-speed math lives in its own file so it can
-- be unit-tested without loading the full player module.
local JumpMath = require "mvtk.player.player_jump_math"
local Grapple = require "mvtk.player.player_grapple"
local SafeGround = require "mvtk.player.safe_ground"
local PoundFeedback = require "mvtk.player.ground_pound_feedback"
local AttackExecutor = require "mvtk.combat.attack_executor"
local PlayerStats = require "mvtk.player.player_stats"
local WallSurfaces = require "mvtk.world.wall_surfaces"
local Abilities = require "mvtk.abilities.ability_manager"
local ColliderGeometry = require "mvtk.player.collider_geometry"
local AirDash = require "mvtk.player.air_dash"
-- Not a literal require: player_host loads features that require this module,
-- and Bob refuses require cycles. player.script requires it literally.
local PLAYER_HOST_MODULE = "mvtk.player.player_host"
local SurfaceEffects = require "mvtk.player.surface_effects"
local M = {}

-- Preserve the movement curves authored for this simulation step.
M.REFERENCE_STEP = Timers.REFERENCE_STEP

-- Apply lift against effective gravity. Existing ascent above the limit is
-- preserved; the limit only applies to the lift contribution.
function M.env_lift(vy, g, dt, multiple, cap)
  if multiple < 0 or (multiple > 0 and vy < cap) then
    local acceleration = multiple * math.abs(g)
    local lifted_vy = vy + acceleration * dt
    if multiple > 0 and lifted_vy > cap then return cap, acceleration, true end
    return lifted_vy, acceleration, false
  end
  return vy
end

function M.apply_env_lift(self, g, dt)
  local multiple, cap = SurfaceEffects.lift(self)
  local vy, acceleration, capped = M.env_lift(self.vy, g, dt, multiple, cap)
  if acceleration then self._jump_cut_pending = nil end
  self.vy = vy
  return acceleration, capped
end

local pstate_log = Util.make_debug_log("[PSTATE]", function()
  return PS.debug_movement
end)

local function glide_debug_enabled()
  return Debug.global.enable or (Debug.gameplay and Debug.gameplay.glide)
end
local glide_log = Util.make_debug_log("[GLIDE]", glide_debug_enabled)

-- Countdowns that keep running while a zip line or loaded cannon owns motion.
local OWNED_TIMERS = { "_jump_hold_t", "_double_jump_t" }
local WALL_TIMERS = { "_wall_contact_timer", "_wall_coyote_t", "_wall_reattach_lock_t" }

local GRAPPLE_GROUP = hash("grapple")

local GRAPPLE_HASHES = {}
local function resolve_grapple_groups(actions, config, rope_check)
  local out, seen, latch = {}, {}, {}
  local function add(groups, terrain)
    for _, name in ipairs(groups) do
      local group = name
      if type(name) == "string" then
        GRAPPLE_HASHES[name] = GRAPPLE_HASHES[name] or hash(name)
        group = GRAPPLE_HASHES[name]
      end
      if terrain then latch[group] = true end
      if not seen[group] then out[#out + 1], seen[group] = group, true end
    end
  end
  add(config.block_groups or actions.block_groups or { "solid", "world" })
  add({ GRAPPLE_GROUP })
  if not rope_check and (config.targets or actions.targets or "surfaces") == "ceilings" then
    add(config.latch_groups or actions.latch_groups or { "solid", "world" }, true)
  end
  return out, latch
end


local compute_jump_speed = JumpMath.compute_jump_speed

local compute_extended_jump_speed = JumpMath.compute_extended_jump_speed

local function ledge_config(self)
  local wall_climb = self and self._cfg and self._cfg.wall_climb
  local cfg = wall_climb and wall_climb.ledge_climb
  return type(cfg) == "table" and cfg or {}
end

local function animated_ledge_hang_enabled(self, cfg)
  cfg = cfg or ledge_config(self)
  return cfg.enabled == true and cfg.hang_enabled == true and self._ledge_hang_supported == true
end

local function copy_player_position(self)
  if self and self.pos then
    return vmath.vector3(self.pos)
  end
  return vmath.vector3(go.get_position())
end

local function set_player_position(self, position)
  self.pos = vmath.vector3(position)
  go.set_position(self.pos)
end

local function input_is_away_from_wall(side, move_x, threshold)
  if side == 0 then return false end
  threshold = threshold or 0.20
  return (side < 0 and move_x >= threshold)
    or (side > 0 and move_x <= -threshold)
end

--- Clear transient ledge-hang/climb state without changing renderer support.
-- This is public so player reset/respawn paths can clear the kinematic state.
function M.clear_ledge_state(self)
  self._ledge_hanging = false
  self._ledge_climbing = false
  self._ledge_kinematic = false
  self._ledge_hang_side = 0
  self._ledge_climb_side = 0
  Timers.clear_window(self, "_ledge_climb_window")
  self._ledge_climb_t = 0
  self._ledge_climb_duration = 0
  self._ledge_climb_start = nil
  self._ledge_climb_target = nil
  self._ledge_climb_authored_target = nil
  self._ledge_climb_last_safe = nil
  self._ledge_climb_collision = nil
  self._ledge_climb_blocked_reason = nil
  self._ledge_climb_aborted = false
  self._ledge_climb_started = false
  self._ledge_climb_completed = false
end

--- Enter a stationary ledge hang and snap flush to the sampled wall face.
function M.enter_ledge_hang(self, wall_side, center_hit)
  if self._pound_active or not M.wall_can_climb(self) then return false end
  local side = tonumber(wall_side) or 0
  if side == 0 or self._ledge_climbing then return false end
  side = (side < 0) and -1 or 1

  local p = copy_player_position(self)
  if center_hit and center_hit.position and center_hit.position.x then
    local half_width = self.collider_half_width or 30
    p.x = center_hit.position.x - side * (half_width + 0.25)
  end
  set_player_position(self, p)

  self._ledge_hanging = true
  self._ledge_climbing = false
  self._ledge_kinematic = true
  self._ledge_hang_side = side
  self._ledge_climb_side = 0
  self._ledge_climb_started = false
  self._ledge_climb_completed = false
  self._on_wall = true
  self._wall_side = side
  self._wall_last_side = side
  Timers.extend_window(self, "_wall_contact_timer",
    (self._cfg.wall_climb and self._cfg.wall_climb.contact_grace) or 0.12)
  self.grounded = false
  self.facing = side
  self._jump_cut_pending = nil
  self.vx, self.vy = 0, 0
  return true
end

--- Begin the kinematic hang-to-ledge interpolation.
function M.start_ledge_climb(self)
  if not self._ledge_hanging or self._ledge_climbing then return false end
  local cfg = ledge_config(self)
  local side = self._ledge_hang_side ~= 0 and self._ledge_hang_side or self._wall_side
  if side == 0 then return false end

  local start = copy_player_position(self)
  local duration = math.max(0.001, tonumber(cfg.climb_time) or 0.45)
  -- Animated Edge_Climb moves toward/over the wall top. The opposite sign is
  -- retained only by instant_ledge_climb() for strict legacy compatibility.
  local authored_target = vmath.vector3(
    start.x + ((cfg.climb_x or 32) * side),
    start.y + (cfg.climb_y or 64),
    start.z)
  local support, support_reason = BonePhysics.probe_ledge_support(self, authored_target, start)
  if not support then
    self._ledge_climb_blocked_reason = support_reason or "no_support"
    M.release_ledge_hang(self, { down_input = 0 })
    return false
  end
  local target = support.position

  self._ledge_hanging = false
  self._ledge_climbing = true
  self._ledge_kinematic = true
  self._ledge_climb_started = true
  self._ledge_climb_completed = false
  self._ledge_climb_side = side
  Timers.start_window(self, "_ledge_climb_window", duration)
  self._ledge_climb_t = 0
  self._ledge_climb_duration = duration
  self._ledge_climb_start = start
  self._ledge_climb_target = target
  self._ledge_climb_authored_target = authored_target
  self._ledge_climb_last_safe = vmath.vector3(start)
  self._ledge_climb_collision = nil
  self._ledge_climb_blocked_reason = nil
  self._ledge_climb_aborted = false
  self._on_wall = false
  self._wall_side = 0
  Timers.clear_window(self, "_wall_contact_timer")
  Timers.clear_window(self, "_wall_coyote_t")
  Timers.extend_window(self, "_wall_reattach_lock_t", duration + 0.05)
  self.grounded = false
  self.facing = side
  self.vx, self.vy = 0, 0
  return true
end

local function abort_ledge_climb(self, reason)
  self._ledge_climbing = false
  self._ledge_kinematic = false
  self._ledge_climb_started = false
  self._ledge_climb_completed = false
  self._ledge_climb_collision = nil
  self._ledge_climb_blocked_reason = reason or "blocked"
  self._ledge_climb_aborted = true
  Timers.clear_window(self, "_ledge_climb_window")
  self._on_wall = false
  self._wall_side = 0
  Timers.clear_window(self, "_wall_contact_timer")
  Timers.extend_window(self, "_wall_reattach_lock_t", 0.18)
  self.grounded = false
  self.vx, self.vy = 0, 0
end

local function advance_ledge_climb(self, dt)
  local start = self._ledge_climb_start
  local target = self._ledge_climb_target
  if not (start and target) then
    M.clear_ledge_state(self)
    return
  end

  local duration = math.max(0.001, self._ledge_climb_duration or 0.45)
  if self._ledge_climb_window == nil then
    -- An in-progress climb can survive a script reload.
    Timers.start_window(self, "_ledge_climb_window", duration, false, self._ledge_climb_t)
  end
  Timers.tick_window(self, "_ledge_climb_window", dt)
  local complete = self._ledge_climb_window <= 0
  if complete then
    self._ledge_climb_t = duration
  else
    self._ledge_climb_t = math.min(duration, (self._ledge_climb_t or 0) + math.max(dt, 0))
  end
  local t = self._ledge_climb_t / duration
  -- Rise clear of the wall first, then translate over its top. A direct
  -- diagonal root lerp would necessarily sweep the collider through the wall.
  local rise_fraction = 0.55
  local desired
  if t <= rise_fraction then
    local rise_t = t / rise_fraction
    desired = vmath.vector3(
      start.x,
      start.y + ((target.y - start.y) * rise_t),
      start.z + ((target.z - start.z) * rise_t))
  else
    local across_t = (t - rise_fraction) / (1 - rise_fraction)
    desired = vmath.vector3(
      start.x + ((target.x - start.x) * across_t),
      target.y,
      start.z + ((target.z - start.z) * t))
  end

  local final_support
  if complete then
    local authored_target = self._ledge_climb_authored_target or target
    final_support, self._ledge_climb_blocked_reason = BonePhysics.probe_ledge_support(
      self, authored_target, start)
    if not final_support then
      abort_ledge_climb(self, self._ledge_climb_blocked_reason or "no_support")
      return
    end
    desired = final_support.position
  end

  local current = copy_player_position(self)
  local clear, blocked_reason = BonePhysics.sweep_ledge_motion(self, current, desired)
  if not clear then
    abort_ledge_climb(self, blocked_reason)
    return
  end

  set_player_position(self, desired)
  self._ledge_climb_last_safe = vmath.vector3(desired)
  self.vx, self.vy = 0, 0

  if complete then
    self._ledge_climbing = false
    self._ledge_kinematic = false
    self._ledge_climb_completed = true
    self._ledge_climb_collision = final_support.collision
    self._on_wall = false
    self._wall_side = 0
    Timers.clear_window(self, "_wall_contact_timer")
    -- player.script routes this real support collision through set_grounded().
    self.grounded = false
  end
end

-- Surface forces use base player units; inherited impulses keep existing math.
function M.wall_jump_forces(self, rule, wall_jump)
  local scale = self._cfg.scale_movement ~= false and (tonumber(self._cfg.player_scale) or 1) or 1
  local x, y = rule and tonumber(rule.jump_force_x), rule and tonumber(rule.jump_force_y)
  return x and x >= 0 and x * scale or (wall_jump.push_h or 1400),
    y and y >= 0 and y * scale or (wall_jump.push_v or self._jump_speed)
end

function M.start_wall_jump_steering(self, wall_side, wall_jump)
  local duration = wall_jump.steer_lock or 0
  if duration > 0 then
    self._wall_jump_steering = { direction = -wall_side }
    Timers.start_window(self._wall_jump_steering, "remaining", duration)
    self.facing = -wall_side
  end
end

function M.wall_can_climb(self)
  local rule = self._wall_rule
  return not rule or (rule.allow_climb ~= false and rule.allow_slide ~= false)
end

--- Release a hang either downward or as a wall jump away from the ledge.
function M.release_ledge_hang(self, opts)
  opts = opts or {}
  if not self._ledge_hanging then return false end
  self._vertical_grid = nil
  self._jump_cut_pending = nil
  local side = self._ledge_hang_side ~= 0 and self._ledge_hang_side or self._wall_side
  local wall_climb = self._cfg.wall_climb or {}
  local wall_jump = wall_climb.wall_jump or {}

  self._ledge_hanging = false
  self._ledge_kinematic = false
  self._ledge_hang_side = 0
  self._ledge_climb_started = false
  self._ledge_climb_completed = false
  self._on_wall = false
  self._wall_side = 0
  self._wall_time = 0
  Timers.clear_window(self, "_wall_contact_timer")
  Timers.start_window(self, "_wall_coyote_t", wall_jump.coyote_time or 0)
  Timers.extend_window(self, "_wall_reattach_lock_t",
    wall_climb.reattach_lock or wall_jump.reattach_lock or 0.18)

  if opts.jump_away then
    local rule = self._wall_rule or self._wall_last_rule
    if wall_jump.enabled ~= false and (not rule or rule.allow_jump ~= false) then
      local push_h, push_v = M.wall_jump_forces(self, rule, wall_jump)
      self.vx = -side * push_h
      self.vy = push_v
      M.start_wall_jump_steering(self, side, wall_jump)
      self._jump_cut_pending = true
      -- The impulse supplies jump speed; it must not unlock ground running.
    else
      self.vx = -side * (wall_climb.detach_push or 220)
      self.vy = 0
    end
  else
    self.vx = 0
    self.vy = (wall_climb.climb_speed or 800) * (opts.down_input or -1)
  end
  return true
end

local function instant_ledge_climb(self, cfg)
  cfg = cfg or ledge_config(self)
  local side = self._wall_side or 0
  if side == 0 then return false end
  self._vertical_grid = nil
  local p = copy_player_position(self)
  p.x = p.x + ((cfg.climb_x or 32) * (side < 0 and 1 or -1))
  p.y = p.y + (cfg.climb_y or 64)
  set_player_position(self, p)
  M.clear_ledge_state(self)
  self._on_wall = false
  self._wall_side = 0
  self._wall_time = 0
  self.grounded = false
  self._jump_cut_pending = nil
  self.vy = math.max(self.vy or 0, 0)
  return true
end

--- Revoke animated ledge support after renderer playback reports a missing
-- required animation. If Edge_Climb had already begun, rewind its small
-- kinematic advance and execute the exact legacy away/up teleport instead.
function M.on_ledge_animation_missing(self)
  self._ledge_hang_supported = false

  if self._ledge_climbing then
    local start = self._ledge_climb_start and vmath.vector3(self._ledge_climb_start)
      or copy_player_position(self)
    local side = self._ledge_climb_side ~= 0 and self._ledge_climb_side
      or self._ledge_hang_side
      or self._wall_last_side
      or 0
    set_player_position(self, start)
    M.clear_ledge_state(self)
    if side ~= 0 then
      self._on_wall = true
      self._wall_side = side
      self._wall_last_side = side
      self.grounded = false
      return instant_ledge_climb(self, ledge_config(self))
    end
    return false
  end

  if self._ledge_hanging then
    local side = self._ledge_hang_side ~= 0 and self._ledge_hang_side
      or self._wall_side
      or 0
    M.clear_ledge_state(self)
    self._on_wall = side ~= 0
    self._wall_side = side
    self._wall_last_side = side
    Timers.start_window(self, "_wall_contact_timer", (self._cfg.wall_climb and self._cfg.wall_climb.contact_grace) or 0.12)
    self.grounded = false
    self.vx, self.vy = 0, 0
  end
  return false
end

function M.interrupt_window_handoffs(self)
  self._compact_roll_exit, self._slide_exit_elapsed, self._dash_exit_elapsed = nil, nil, nil
  -- A rounded-zero pulse may still owe part of the next ordinary steering
  -- frame. An interruption ends that handoff without clearing a live timer.
  if self._autorun_nudge_t == 0 then Timers.discard_window(self, "_autorun_nudge_t") end
end

-- Clear PSTATE-owned transient ability fields. Feature-owned state resets
-- in its own PlayerHost hook. Safe on a fresh self for init and every reset reason.
function M.reset_ability_state(self, reason)
  self._jump_cut_pending = nil
  self._vertical_grid = nil
  M.interrupt_window_handoffs(self)
  if self._autorun_nudge_t ~= nil then
    Timers.start_window(self, "_autorun_nudge_t", 0)
  end
  self._wall_jump_steering = nil
  self._dash_vy, self._dash_vertical_exited = nil, nil
  self._last_dash_dir_y = nil
  self._super_jump_ready, self._super_jump_rising = nil, nil
  self._super_jump_started = nil
end

function M.init(self, overrides)
  M.reset_ability_state(self, "init")
  -- Merge per-instance overrides with defaults from settings
  self._cfg = setmetatable(overrides or {}, { __index = PS })
  self.vx, self.vy = 0, 0
  self.facing = 1
  self.grounded = false
  self._jump_speed = compute_jump_speed(self._cfg)
  self._extended_jump_speed = compute_extended_jump_speed(self._cfg)
  self._run_gate = false
  self._slide_t = 0
  self._slide_cool = 0
  self._slide_recovery_t = 0
  -- Jump helpers / timers
  Timers.clear_window(self, "_coyote_t")
  Timers.clear_window(self, "_jump_buffer_t")
  self._jump_hold_t = 0
  self._extra_jumps = self._cfg.air_jumps or 0
  self._double_jump_t = 0  -- Timer to track double jump animation
  -- Air dash state
  self._dash_t = 0
  self._dash_cool = 0
  self._last_dash_dir = 0
  self._air_dashes_left = (self._cfg.air_dash and self._cfg.air_dash.max_air_dashes) or 1
  self._last_mode = nil
  self._autorun_nudge_t = 0
  self._autorun_dir = 0
  -- iFrames state
  self._invulnerable, self._movement_iframes = false, false
  self._parry_iframes_t = 0
  self._slide_iframes_t, self._dash_iframes_t = 0, 0
  self._stun_t = 0
  -- Backdash
  self._backdash_t = 0
  self._backdash_cool = 0
  self._pound_active = false
  self._pound_recovery_t = 0
  self._pound_cool = 0
  -- Swim state
  self._in_water = false
  -- Runtime gravity multiplier (for gravity fields, etc.)
  self._gravity_mult = 1.0
  -- Wall climb state
  self._wall_rule, self._wall_last_rule = nil, nil
  self._on_wall = false
  self._wall_side = 0  -- -1 = left wall, 1 = right wall, 0 = no wall
  self._wall_time = 0
  Timers.clear_window(self, "_wall_contact_timer")
  Timers.clear_window(self, "_wall_coyote_t")
  Timers.clear_window(self, "_wall_reattach_lock_t")
  Timers.clear_window(self, "_climb_reattach_lock_t")
  -- Optimistically enable the bundled animations, but preserve an explicit
  -- false supplied by a custom renderer. animation_controller revokes this at
  -- runtime if either required animation fails to play.
  if self._ledge_hang_supported == nil then
    self._ledge_hang_supported = true
  end
  M.clear_ledge_state(self)
  -- Extended jump state
  self._extended_jump_active = false
  self._extended_jump_hold_time = 0
  self._extended_jump_hang_time = 0
  self._extended_jump_bonus_applied = false
  -- Grapple
  Grapple.clear(self)
end

--- Refresh cached ability values from config.
-- Call this after abilities are unlocked to update movement capabilities immediately.
function M.refresh_abilities(self)
  if not self._cfg then return end
  if not (self._cfg.slide_to_run and self._cfg.slide_to_run.enabled) then self._run_gate = false end
  
  -- Update extra jumps (double jump capability)
  local new_air_jumps = self._cfg.air_jumps or 0
  if self.grounded then
    -- If grounded, set directly
    self._extra_jumps = new_air_jumps
  elseif new_air_jumps > (self._extra_jumps or 0) then
    -- If in air and new value is higher, increase available jumps
    self._extra_jumps = new_air_jumps
  end
  
  -- Update air dashes
  local new_max_dashes = (self._cfg.air_dash and self._cfg.air_dash.max_air_dashes) or 1
  if self.grounded then
    self._air_dashes_left = new_max_dashes
  elseif new_max_dashes > (self._air_dashes_left or 0) then
    self._air_dashes_left = new_max_dashes
  end
  
  pstate_log(string.format("[PSTATE] Abilities refreshed: air_jumps=%d air_dashes=%d slide=%s wall_climb=%s",
    self._extra_jumps or 0,
    self._air_dashes_left or 0,
    tostring(self._cfg.slide and self._cfg.slide.enabled),
    tostring(self._cfg.wall_climb and self._cfg.wall_climb.enabled)))
end

-- Height scales with launch speed squared; the normal speed already includes Player Size.
function M.ground_jump_speed(self)
  local config = self._cfg.high_jump
  if config and config.enabled then
    local height_mult = tonumber(config.height_mult) or 1.5
    return self._jump_speed * math.sqrt(math.max(1, height_mult))
  end
  return self._jump_speed
end

function M.set_grounded(self, g)
  local was_grounded = self.grounded and true or false
  if was_grounded ~= (g and true or false) then self._vertical_grid = nil end
  self.grounded = g and true or false
  if self.grounded then
    self._jump_cut_pending = nil
    self._grapple_carry_t = 0
    self._grapple_flight = false
    -- A floor contact ends wall movement, including the late-jump grace.
    -- Otherwise the next ground jump can reuse the wall push and reattach.
    self._on_wall, self._wall_sliding = false, false
    self._wall_side, self._wall_last_side, self._wall_time = 0, 0, 0
    self._wall_rule, self._wall_last_rule = nil, nil
    Timers.clear_window(self, "_wall_coyote_t")
    Timers.clear_window(self, "_wall_contact_timer")
    Timers.clear_window(self, "_wall_reattach_lock_t")
    if not was_grounded then
    self._wall_jump_steering = nil
    -- A downward dash ends at the floor; keep horizontal momentum.
    if (self._dash_t or 0) > 0 and (self._last_dash_dir_y or 0) < 0 then
      self._dash_t = 0
      self._dash_iframes_t = 0
      M.tick_iframes(self, 0)
      self._control_locked = false
      self._dash_vy = nil
      self._last_dash_dir_y = nil
      self._last_dash_dir = 0
      if Audio and Audio.stop_sfx then Audio.stop_sfx("air_dash") end
    end
    -- Landed: clear coyote, restore air resources, clamp landing vy
    Timers.clear_window(self, "_coyote_t")
    self._air_dashes_left = (self._cfg.air_dash and self._cfg.air_dash.max_air_dashes) or 1
    self._extra_jumps = self._cfg.air_jumps or 0
    if self.vy < 0 then self.vy = 0 end
    -- SFX: land
    if Audio and Audio.sfx then Audio.sfx("land") end
    -- Clear extended jump state on landing
    if self._extended_jump_active then
      self._extended_jump_active = false
      self._extended_jump_hold_time = 0
      self._extended_jump_hang_time = 0
      self._extended_jump_bonus_applied = false
    end
    -- Buffered jump: if a jump was buffered, perform it now as a ground jump
    if (self._jump_buffer_t or 0) > 0 then
      self.vy = M.ground_jump_velocity(self)
      self._jump_cut_pending = true
      self.grounded = false
      Timers.clear_window(self, "_coyote_t")
      Timers.clear_window(self, "_jump_buffer_t")
      self._jump_hold_t = self._cfg.jump_min_hold_time or 0
    end
    end
  else
    -- Left ground this frame: start coyote timer
    if was_grounded then
      Timers.start_window(self, "_coyote_t", self._cfg.coyote_time or 0)
    end
  end
  SafeGround.observe(self)
end

-- Scale ordinary jump impulses after High Jump. Wall jumps, ladder jump-off,
-- grapple hang releases and swing momentum retain their authored velocities.
function M.jump_velocity(self, base)
  return base * PlayerStats.mult("jump_mult")
end

-- Scale the ordinary ground jump's height using effective walk and run speeds.
function M.ground_jump_velocity(self)
  local speed = M.jump_velocity(self, M.ground_jump_speed(self))
  local bonus = self._cfg.speed_jump_bonus or 0
  if bonus > 0 then
    local speed_mult = PlayerStats.mult("speed_mult")
    local walk_speed = (self._cfg.walk_speed or 1200) * speed_mult
    local run_speed = (self._cfg.run_speed or 2000) * speed_mult
    local takeoff_speed = math.abs(self.vx)
    if run_speed > walk_speed and takeoff_speed > walk_speed then
      local share = Util.clamp((takeoff_speed - walk_speed) / (run_speed - walk_speed), 0, 1)
      speed = speed * math.sqrt(1 + bonus * share)
    end
  end
  return speed
end

local function ground_jump(self, boost_ground)
  self._vertical_grid = nil
  -- Check for extended jump
  if self._cfg.extended_jump and self._cfg.extended_jump.enabled then
    self._extended_jump_active = true
    self._extended_jump_hold_time = 0
    self._extended_jump_hang_time = 0
    self._extended_jump_bonus_applied = false
    if self._cfg.debug_movement then
      pstate_log(string.format("%s Jump started - extended jump tracking enabled (speed=%.1f)",
        self._cfg.debug_tag or "[PSTATE]", self._extended_jump_speed or 0))
    end
  else
    if self._cfg.debug_movement then
      pstate_log(string.format("%s Jump started - extended jump NOT enabled (cfg=%s, enabled=%s)",
        self._cfg.debug_tag or "[PSTATE]",
        tostring(self._cfg.extended_jump ~= nil),
        tostring(self._cfg.extended_jump and self._cfg.extended_jump.enabled)))
    end
  end
  self.vy = boost_ground and M.ground_jump_velocity(self) or self._jump_speed
  -- The unboosted call is the stationary grapple hang dismount.
  self._jump_cut_pending = boost_ground
  if Audio and Audio.sfx then Audio.sfx("jump") end
  self.grounded = false
  Timers.clear_window(self, "_coyote_t")
  self._jump_hold_t = self._cfg.jump_min_hold_time or 0
  -- Cancel slide on jump if configured
  if self._slide_t > 0 and self._cfg.slide and self._cfg.slide.cancel_on_jump then
    self._slide_t = 0
    self._slide_iframes_t = 0
    M.tick_iframes(self, 0)
    self._control_locked = false
  end
  -- Exit wall climbing when jumping (from ground/coyote)
  M.exit_wall_climb(self)
  return true
end

function M.request_jump(self, input_opt)
  if self._carry_blocks_jump then return false end
  -- A zip line ride or loaded cannon consumes the press; never spend or buffer it.
  if require(PLAYER_HOST_MODULE).holds_presses(self) then return false end
  if self._compact_active then return require("mvtk.player.compact_form").jump(self) end
  local input = input_opt or self._last_input or { move_x = 0, move_y = 0, jump_held = false }
  if self._pound_active then
    -- The committed slam cannot be replaced by an air, wall or ledge jump.
    -- Keep the ordinary buffer so a press just before landing can still win.
    Timers.extend_window(self, "_jump_buffer_t", self._cfg.jump_buffer or 0)
    return false
  end
  if self._grapple_hanging then
    Grapple.release(self, input, ACTIONS.grapple, self._cfg.grapple, "hang_jump")
    return ground_jump(self)
  end
  if self._grapple_active and Grapple.release_on_jump(ACTIONS.grapple, self._cfg.grapple) then
    return Grapple.release(self, input, ACTIONS.grapple, self._cfg.grapple, "let_go")
  end
  -- A new jump owns the ascent, so its early-release gravity applies again.
  self._grapple_flight = false
  -- Wall jump (takes priority if on wall or within wall coyote window)
  local WC = self._cfg.wall_climb
  local WJ = (WC and type(WC.wall_jump) == "table") and WC.wall_jump or {}
  -- With wall climb, wall jump is on unless explicitly disabled; without it,
  -- wall jump needs its own unlock (wall slide mode).
  local wall_jump_enabled = WC and ((WC.enabled and WJ.enabled ~= false) or (not WC.enabled and WJ.enabled == true))
  local LC = ledge_config(self)
  local move_x = input.move_x or 0
  local move_y = input.move_y or 0
  local away_threshold = (WC and WC.detach_away_threshold) or 0.20

  -- Jump input arrives through on_input() before the frame update. Consume it
  -- here while hanging so the generic wall-jump path cannot clear the hang
  -- before Edge_Climb is requested.
  if self._ledge_climbing then
    return true
  elseif self._ledge_hanging then
    if move_y < -0.8 then
      return M.release_ledge_hang(self, { down_input = move_y })
    end
    if input_is_away_from_wall(self._ledge_hang_side, move_x, away_threshold) then
      return M.release_ledge_hang(self, { jump_away = true })
    end
    return M.start_ledge_climb(self)
  end

  if WC and WC.enabled and self._on_wall and LC.enabled and M.wall_can_climb(self) then
    if animated_ledge_hang_enabled(self, LC) then
      local is_lip, center_hit = BonePhysics.probe_ledge_lip(self, self._wall_side)
      if is_lip and M.enter_ledge_hang(self, self._wall_side, center_hit) then
        if move_y < -0.8 then
          return M.release_ledge_hang(self, { down_input = move_y })
        end
        if input_is_away_from_wall(self._ledge_hang_side, move_x, away_threshold) then
          return M.release_ledge_hang(self, { jump_away = true })
        end
        return M.start_ledge_climb(self)
      end
    elseif move_y >= (LC.up_threshold or 0.6) then
      -- Exact legacy up+jump fallback for disabled/unsupported hang animations.
      return instant_ledge_climb(self, LC)
    end
  end

  local wall_rule = self._on_wall and self._wall_rule or self._wall_last_rule
  local detached_contact = wall_rule and wall_rule.allow_slide == false
    and (self._wall_contact_timer or 0) > 0 and (self._wall_last_side or 0) ~= 0
    and (self._wall_reattach_lock_t or 0) <= 0
  if wall_jump_enabled and (self._on_wall or detached_contact or (self._wall_coyote_t or 0) > 0)
    and (not wall_rule or wall_rule.allow_jump ~= false) then
    -- Determine the wall side to jump from (use last-known side during coyote)
    local side = (self._on_wall and self._wall_side ~= 0) and self._wall_side or (self._wall_last_side or 0)
    if side == 0 then side = (self.facing ~= 0 and self.facing or 1) end
    -- Enforce input requirement (toward/away/either) for a proper wall jump
    local mode = WJ.input_mode or "toward"
    local th = WJ.input_threshold or 0.25
    local allow_neutral = (WJ.input_allow_neutral ~= false)
    local mx = input.move_x or 0
    local ok = false
    if allow_neutral and math.abs(mx) < th then ok = true end
    if not ok then
      if mode == "toward" then
        ok = (side < 0 and mx <= -th) or (side > 0 and mx >= th)
      elseif mode == "away" then
        ok = (side < 0 and mx >= th) or (side > 0 and mx <= -th)
      else -- either
        ok = math.abs(mx) >= th
      end
    end
    if not ok then
      if self._cfg.debug_movement then
        pstate_log(string.format("%s WALL JUMP BLOCKED: input not %s (move_x=%.2f, th=%.2f)", self._cfg.debug_tag or "[PSTATE]", tostring(mode), mx, th))
      end
      return false
    end
    local dir = side
    local push_h, push_v = M.wall_jump_forces(self, wall_rule, WJ)
    -- Push away from wall: wall_side -1 (left wall) -> push right (+), 1 (right wall) -> push left (-)
    self.vx = -dir * push_h
    self._vertical_grid = nil
    self.vy = push_v
    M.start_wall_jump_steering(self, side, WJ)
    self._jump_cut_pending = true
    Timers.clear_window(self, "_wall_coyote_t")
    Timers.clear_window(self, "_wall_contact_timer")
    Timers.start_window(self, "_wall_reattach_lock_t", WJ.reattach_lock or 0.18)
    self._on_wall = false
    self._wall_side = 0
    -- Preserve the existing locomotion mode. A wall impulse is not a run unlock.
    if self._cfg.debug_movement then
      pstate_log(string.format("%s WALL JUMP: push_h=%.0f push_v=%.0f", self._cfg.debug_tag or "[PSTATE]", push_h, push_v))
    end
    return true
  end

  -- A charged launch uses base jump height; High Jump does not multiply it.
  if self._super_jump_ready and self.grounded
    and math.abs(input.move_x or 0) < ((self._cfg.super_jump or {}).still_threshold or 0.25)
    and not self._in_water and not self._in_climb and not self._compact_active
    and not self._attack and not (self._combat and self._combat.current)
    and not self._is_dead and (self._stun_t or 0) <= 0
    and self._ability_can_use and self._ability_can_use("super_jump") then
    self._vertical_grid = nil
    self.vy = self._jump_speed * math.sqrt(math.max(1, (self._cfg.super_jump or {}).launch_height_mult or 3))
    self._jump_cut_pending = nil
    self.vx = 0
    self.grounded = false
    Timers.clear_window(self, "_coyote_t")
    Timers.clear_window(self, "_jump_buffer_t")
    self._super_jump_ready, self._super_jump_rising = false, true
    self._super_jump_started = true -- Preserve the launch edge through same-frame ceiling resolution.
    self._control_locked = (self._cfg.super_jump or {}).lock_horizontal ~= false
    self._extended_jump_active = false
    self._ability_use("super_jump")
    return true
  end
  -- Ground / coyote jump
  if self.grounded or ((self._coyote_t or 0) > 0) then
    return ground_jump(self, true)
  end
  -- Air jump if available
  if (self._extra_jumps or 0) > 0 then
    self._vertical_grid = nil
    self.vy = M.jump_velocity(self, self._cfg.high_jump and self._cfg.high_jump.apply_to_air_jumps
      and M.ground_jump_speed(self) or self._jump_speed)
    self._jump_cut_pending = true
    if Audio and Audio.sfx then Audio.sfx("double_jump") end
    self._extra_jumps = self._extra_jumps - 1
    self._double_jump_t = 0.4  -- Set timer for double jump animation
    self._jump_hold_t = self._cfg.jump_min_hold_time or 0
    if self._cfg.debug_movement then
      pstate_log(string.format("%s Double jump used! Remaining: %d", 
        self._cfg.debug_tag or "[PSTATE]", self._extra_jumps))
    end
    -- Exit wall climbing when double jumping
    M.exit_wall_climb(self)
    return true
  end
  -- Could not jump now: buffer it
  Timers.extend_window(self, "_jump_buffer_t", self._cfg.jump_buffer or 0)
  return false
end

function M.request_slide_press(self, input, request_swim_dash)
  if self._carry_active then return false end
  if require(PLAYER_HOST_MODULE).holds_presses(self) then return false end
  if self._in_water then
    return request_swim_dash and request_swim_dash(self, input) or false
  end
  -- If airborne, handle air dash first (do not early-return due to slide ground requirements).
  local AD = self._cfg.air_dash
  if AD and AD.enabled and not self.grounded then
    if self._compact_active then return end
    -- A committed slam is not steered by a dash, and a dash ending would unlock it.
    if self._pound_active then return end
    if (self._dash_cool or 0) > 0 then
      if ((self._dash_t or 0) > 0 or (self._teleport_chain_t or 0) > 0)
        and self._ability_can_use and self._ability_can_use("blink") then
        self._teleport_request = { x = input and input.move_x, y = input and input.move_y, frame = self._frame_counter }
        return true
      end
      return
    end
    if (self._air_dashes_left or 0) <= 0 then return end
    -- A successful dash takes ownership of movement. Failed requests leave
    -- the hook intact and never spend an air-dash charge.
    Grapple.clear(self)
    Timers.start_window(self, "_dash_t", AD.duration or 0.18, true)
    Timers.start_window(self, "_dash_iframes_t", AD.iframe_seconds or 0, true)
    Timers.start_window(self, "_dash_cool", (AD.cooldown or 0.20) + self._dash_t)
    local s = AD.speed or 1400
    local dir, dy = AirDash.direction(input, self.facing, self._on_wall, self._wall_side, AD)
    self._wall_jump_steering = nil
    self.vx = s * dir
    self._last_dash_dir = dir
    self._last_dash_dir_y = nil
    self._dash_vy, self._dash_vertical_exited = nil, nil
    if AD.directions == "eight" then
      self._vertical_grid = nil
      self._jump_cut_pending = nil
      self.vy = s * dy
      self._last_dash_dir_y = dy
      if AD.suspend_gravity ~= false then self._dash_vy = self.vy end
    end
    if Audio and Audio.sfx then Audio.sfx("air_dash") end
    -- Optional: trigger a dash trail FX hook
    if FX and FX.on_dash then pcall(FX.on_dash, { dir = dir }) end
    self._air_dashes_left = math.max(0, (self._air_dashes_left or 0) - 1)
    self._control_locked = true
    -- Exit wall climbing when air dashing
    M.exit_wall_climb(self)
    return true
  end

  -- Down+Slide belongs to Compact Form, including during a ground slide.
  if self.grounded and input and (input.move_y or 0) <= -0.5 then
    if self._compact_active then return end
    if require("mvtk.player.compact_form").enter(self) then return true end
  end
  if self._compact_active then return end

  -- Ground slide (only when grounded)
  if (self._cfg.slide and self._cfg.slide.enabled) and self.grounded then
    if self._cfg.slide.require_grounded and not self.grounded then return end
    if (self._slide_cool or 0) > 0 then
      if ((self._slide_t or 0) > 0 or (self._teleport_chain_t or 0) > 0)
        and self._ability_can_use and self._ability_can_use("blink") then
        self._teleport_request = { x = input and input.move_x, y = input and input.move_y, frame = self._frame_counter }
        return true
      end
      return
    end
    Timers.start_window(self, "_slide_t", self._cfg.slide.duration or 0.28, true)
    Timers.start_window(self, "_slide_iframes_t", self._cfg.slide.iframe_seconds or 0, true)
    Timers.start_window(self, "_slide_cool", (self._cfg.slide.cooldown or 0.15) + self._slide_t)
    local s = self._cfg.slide.speed or 520
    local dir = (self.facing ~= 0 and self.facing or 1)
    self.vx = s * dir
    if Audio and Audio.sfx then
      Audio.sfx("slide", { cooldown = (self._cfg.slide and self._cfg.slide.sound_cooldown) or 0.3 })
    end
    if self._cfg.slide.lock_control then self._control_locked = true end
    if self._cfg.debug_movement then
      pstate_log(string.format("%s SLIDE STARTED: duration=%.3f, speed=%.0f, facing=%d", 
        self._cfg.debug_tag or "[PSTATE]", self._slide_t, s, dir))
    end
    return true
  end
end

function M.request_slide_release(self)
  -- handled in update (run gate clear)
end

-- A successful teleport ends movement ownership without refilling charges or
-- cooldowns. Keep the eight-direction dash cleanup in step with natural expiry.
function M.end_dash_slide(self)
  M.interrupt_window_handoffs(self)
  self._vertical_grid = nil
  self._super_jump_rising = false -- Blink uses this seam even with a positive exit vertical speed.
  self._super_jump_started = nil
  if (self._dash_t or 0) > 0 and self._last_dash_dir_y ~= nil and not self._dash_vertical_exited then
    self._jump_cut_pending = nil
    self.vy = self.vy * (self._cfg.air_dash.end_vertical_speed_mult or 0.35)
  end
  self._dash_t, self._slide_t, self._slide_recovery_t = 0, 0, 0
  self._slide_iframes_t, self._dash_iframes_t = 0, 0
  self._dash_vy, self._last_dash_dir_y, self._dash_vertical_exited = nil, nil, nil
  M.tick_iframes(self, 0)
  self._last_dash_dir = 0
  self._control_locked, self._run_gate = false, false
  M.exit_wall_climb(self)
  if Audio and Audio.stop_sfx then Audio.stop_sfx("air_dash") end
end

function M.request_backdash(self)
  if self._carry_active then return false end
  -- A zip line ride or loaded cannon holds the press, as it does Jump and Dash.
  if require(PLAYER_HOST_MODULE).holds_presses(self) then return false end
  local BD = self._cfg.backdash
  if not (BD and BD.enabled) then return end
  if not self.grounded then return end
  if (self._backdash_cool or 0) > 0 then return end
  Timers.start_window(self, "_backdash_t", BD.duration or 0.16, true)
  Timers.start_window(self, "_backdash_cool", (BD.cooldown or 0.30) + self._backdash_t)
  self._control_locked = true
  local dir = (self.facing ~= 0 and self.facing or 1)
  self.vx = -(BD.speed or 1800) * dir
end

-- The slam owns the player until it lands. An attack in progress ends (an air
-- attack holds the fall back), and attack presses are spent rather than queued
-- for the landing. Heavy is part of the slam input, so that press is spent too.
local function drop_attacks_for_slam(self)
  if self._attack or (self._combat and self._combat.current) then AttackExecutor.cancel(self) end
  self._light_buffer_count, self._heavy_buffer_count, self._ranged_buffer_count = 0, 0, 0
  self._light_hold_t = 0
end

function M.request_ground_pound(self, input)
  if self._carry_active then return false end
  if self._compact_active then return end
  local GP = self._cfg.ground_pound
  if not (GP and GP.enabled) then return end
  if self.grounded then return end
  if (self._pound_active) then return end
  if (self._pound_cool or 0) > 0 then return end
  if self._in_climb or self._in_water or self._grapple_active
    or self._ledge_hanging or self._ledge_kinematic or self._is_dead
    or (self._stun_t or 0) > 0 then return end
  if (self._dash_t or 0) > 0 or (self._slide_t or 0) > 0 then return end
  -- require down input if configured
  local th = GP.require_down_threshold or 0.6
  if input and (input.move_y or 0) > -th then return end
  self._wall_jump_steering = nil
  self._pound_active = true
  self._vertical_grid = nil
  self._control_locked = true
  self.vx = 0
  self._jump_cut_pending = nil
  self.vy = - (GP.slam_speed or 2000)
  drop_attacks_for_slam(self)
end

function M.on_ground_impact(self, pos)
  if self._pound_active then
    local GP = self._cfg.ground_pound or {}
    self._pound_active = false
    self.vx = 0
    Timers.start_window(self, "_pound_cool", GP.cooldown or 0)
    -- set_grounded runs first and may already have consumed a buffered jump.
    -- That player's jump wins over both the automatic pop and its recovery.
    if self.vy > 0 then
      self._pound_recovery_t = 0
    else
      self._jump_cut_pending = nil
      self._vertical_grid = nil
      self.vy = GP.impact_bounce or 0
      Timers.start_window(self, "_pound_recovery_t", GP.recovery or 0, true)
    end
    -- Dust, shake, freeze-frame and rumble (player_actions ground_pound.feedback).
    PoundFeedback.landed(pos)
  end
end

-- Interrupt a committed slam when an involuntary body state takes control.
-- That state owns its velocities and lock; cancellation only retires the slam.
function M.cancel_ground_pound(self)
  if not self._pound_active then return end
  self._pound_active = false
  self._pound_recovery_t = 0
  Timers.start_window(self, "_pound_cool", (self._cfg.ground_pound and self._cfg.ground_pound.cooldown) or 0)
end

function M.set_water(self, v)
  if v then
    self._wall_jump_steering = nil
    M.cancel_ground_pound(self)
    if self._compact_active then require("mvtk.player.compact_form").stand(self) end
  end
  self._in_water = v and true or false
end

-- Runtime gravity multiplier control
function M.set_gravity_mult(self, k)
  self._gravity_mult = (k and tonumber(k)) or 1.0
end

function M.clear_gravity_mult(self)
  self._gravity_mult = 1.0
end

-- Shared by fresh casts and arrival: a flying hook cannot bypass movement locks.
local function grapple_bypassed(self)
  return self._pound_active or self._is_dead or self._in_water or self._in_climb
    or self._attack or self._ledge_kinematic or self._ledge_climb_completed
end

function M.grapple_should_cast(self, input)
  if self._carry_active then return false end
  input = input or {}
  -- These modes suppress fresh presses in player.script or bypass its normal
  -- movement update. A held retry must not bypass the lock or outlive it.
  if self._compact_active or grapple_bypassed(self) then
    self._grapple_recast_t = 0
    return false
  end
  -- Use the aggregated hold, just as rope release does: releasing one binding
  -- must not cancel another binding that still holds Grapple.
  if input.grapple_held == false or (input.grapple_held == nil and input.grapple_up) then
    self._grapple_recast_t = 0
  end
  if self._grapple_active or self._grapple_hook then return false end
  return input.grapple_down == true
    or (input.grapple_held == true and (self._grapple_recast_t or 0) > 0)
end

function M.request_grapple(self, input)
  local G = ACTIONS.grapple or {}
  local CG = self._cfg.grapple or {}
  if grapple_bypassed(self) then
    self._grapple_recast_t = 0
    return false
  end
  if self._grapple_active or self._grapple_hook then return end
  local dx, dy = Grapple.direction(input, self.facing or 1, G, CG)
  local p = self.pos or go.get_position()
  local range = CG.range_px or 300
  if range <= 0 or not physics or not physics.raycast then return false end
  local groups, latch = resolve_grapple_groups(G, CG)
  local room_manager = Util.require_module("mvtk.map.streaming.room_manager")
  local current_room = room_manager and room_manager.get_current_room()
  local opts = { targets = CG.targets or G.targets or "surfaces", grapple_group = GRAPPLE_GROUP,
    latch = latch, allow_walls = CG.allow_walls == true,
    tolerance_px = CG.occlusion_tolerance_px or G.occlusion_tolerance_px or 8,
    ceiling_normal_min = CG.ceiling_normal_min or G.ceiling_normal_min or 0.5,
    wall_normal_min = CG.wall_normal_min or G.wall_normal_min or 0.7 }
  local function cast(x, y)
    if y < 0 then return false end
    local to = vmath.vector3(p.x + x * range, p.y + y * range, p.z)
    local ok, hits = pcall(physics.raycast, p, to, groups, { all = true })
    if not ok or not hits then return false end
    if hits.position then hits = { hits } end
    local hit = Grapple.pick_target(hits, range, opts)
    if not hit then return false end
    local anchor_room = room_manager and room_manager.get_room_for_position(
      vmath.vector3(hit.position.x - x * 2, hit.position.y - y * 2, hit.position.z))
    if anchor_room and current_room and anchor_room ~= current_room then return false end
    if (CG.hook_speed or 0) > 0 then
      local hx, hy = hit.position.x - p.x, hit.position.y - p.y
      self._grapple_hook = {from = vmath.vector3(p),
        hit = {position = vmath.vector3(hit.position), normal = vmath.vector3(hit.normal)},
        distance = math.sqrt(hx * hx + hy * hy), travelled = 0,
        room = current_room, dir = {x = x, y = y}}
      local hook = self._grapple_hook
      Timers.start_window(hook, "travel_t", math.max(M.REFERENCE_STEP, hook.distance / CG.hook_speed))
      self._grapple_recast_t = 0
      self._wall_jump_steering = nil
      return true
    end
    if not Grapple.attach(self, p, hit, G, CG, self.grounded) then return false end
    self._wall_jump_steering = nil
    self._grapple_room_id = current_room
    return true
  end
  if cast(dx, dy) then return true end
  local assist = self.grounded and (CG.aim_assist_deg or G.aim_assist_deg or 12)
    or (CG.aim_assist_air_deg or G.aim_assist_air_deg or 20)
  local step = CG.aim_assist_step_deg or G.aim_assist_step_deg or 6
  local side = input and input.move_x or 0
  if side == 0 then side = self.facing or 1 end
  -- A positive angular rotation points left from straight up.
  local first_sign = side < 0 and 1 or -1
  if step > 0 then
    for angle = step, assist, step do
      for _, sign in ipairs({ first_sign, -first_sign }) do
        local a = math.rad(angle * sign)
        if cast(dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)) then
          return true
        end
      end
    end
  end
  -- Only an actual missed press opens the hold window. A retry miss cannot
  -- extend it, and releases never come through this path to start one.
  if input and input.grapple_down and input.grapple_held ~= false
    and not (input.grapple_held == nil and input.grapple_up) then
    Timers.start_window(self, "_grapple_recast_t", math.max(0, CG.recast_window_s or G.recast_window_s or 0.3))
  end
  return false
end

function M.advance_grapple_hook(self, dt, input)
  local hook = self._grapple_hook
  if not hook then return end
  input = input or {}
  local G, CG = ACTIONS.grapple or {}, self._cfg.grapple or {}
  local HoldToggles = require "mvtk.player.hold_toggles"
  local interrupted = HoldToggles.sync(self, "grapple")
  local stay_hooked = Grapple.effective_stay_hooked(G, CG)
  local release_press = stay_hooked and input.grapple_down
  if release_press then input.grapple_down = false end
  local released = input.grapple_held == false or (input.grapple_held == nil and input.grapple_up)
  local room_manager = Util.require_module("mvtk.map.streaming.room_manager")
  local current_room = room_manager and room_manager.get_current_room()
  if release_press or (not stay_hooked and released) or grapple_bypassed(self)
    or self._carry_active or self._compact_active or (self._stun_t or 0) > 0
    or (interrupted and HoldToggles.enabled("grapple")) or current_room ~= hook.room then
    Grapple.clear(self)
    return
  end
  hook.travelled = math.min(hook.distance, hook.travelled + math.max(0, CG.hook_speed or 0) * math.max(0, dt))
  if Timers.has_window(hook, "travel_t") then
    if not Timers.tick_deadline(hook, "travel_t", dt) then return end
  elseif hook.travelled < hook.distance then return end
  -- A catch is checked against the captured point, not a moving target's new location.
  -- Match attached-rope validation: extend through the surface by its tolerance.
  self._grapple_hook, self._grapple_recast_t = nil, 0
  local anchor = hook.hit.position
  local anchor_room = room_manager and room_manager.get_room_for_position(
    vmath.vector3(anchor.x - hook.dir.x * 2, anchor.y - hook.dir.y * 2, anchor.z))
  if anchor_room and current_room and anchor_room ~= current_room then return end
  local p = self.pos or go.get_position()
  local dx, dy = anchor.x - p.x, anchor.y - p.y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance <= 0 then return end
  local tol = CG.occlusion_tolerance_px or G.occlusion_tolerance_px or 8
  local to = vmath.vector3(anchor.x + dx / distance * tol, anchor.y + dy / distance * tol, anchor.z)
  local hit
  if physics and physics.raycast then
    -- Parentheses keep the latch set out of raycast's options argument.
    local ok, result = pcall(physics.raycast, p, to, (resolve_grapple_groups(G, CG, true)))
    if ok then hit = result end
  end
  if Grapple.rope_state(hit, distance + tol, distance, tol) == "lost" then return end
  -- Check before attach clears grounded, dash and jump-buffer state. A resource
  -- spent by another ability during flight must leave an ordinary miss.
  if self._ability_can_use and not self._ability_can_use("grapple") then return end
  if not Grapple.attach(self, p, hook.hit, G, CG, self.grounded) then return end
  self._wall_jump_steering = nil
  self._grapple_room_id = current_room
  return "caught"
end

function M.draw_grapple_rope(self)
  Grapple.draw_rope(self, ACTIONS.grapple, self._cfg and self._cfg.grapple)
end

function M.cancel_grapple(self)
  Grapple.clear(self)
end

function M.grapple_contacts(self, collision)
  return Grapple.on_contacts(self, collision, ACTIONS.grapple, self._cfg.grapple)
end

local function validate_grapple(self, input)
  if not self._grapple_active or not self._grapple_anchor then return end
  local room_manager = Util.require_module("mvtk.map.streaming.room_manager")
  if self._grapple_room_id and room_manager and room_manager.get_current_room() ~= self._grapple_room_id then
    Grapple.release(self, input, ACTIONS.grapple, self._cfg.grapple, "room")
    return
  end
  local G, CG = ACTIONS.grapple or {}, self._cfg.grapple or {}
  local rope_check = CG.rope_check
  if rope_check == nil then rope_check = G.rope_check end
  if rope_check == false then return end
  local p, anchor = self.pos or go.get_position(), self._grapple_anchor
  local dx, dy = anchor.x - p.x, anchor.y - p.y
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance <= 0 then return end
  local tol = CG.occlusion_tolerance_px or G.occlusion_tolerance_px or 8
  local to = vmath.vector3(anchor.x + dx / distance * tol, anchor.y + dy / distance * tol, anchor.z)
  local hit
  if physics and physics.raycast then
    -- Parentheses keep the second return (latch set) out of raycast's options.
    local ok, result = pcall(physics.raycast, p, to, (resolve_grapple_groups(G, CG, true)))
    if ok then hit = result end
  end
  if Grapple.rope_state(hit, distance + tol, distance, tol) == "lost" then
    Grapple.release(self, input, G, CG, "lost")
  end
end

function M.is_invulnerable(self, hit)
  if self._movement_iframes or (self._invulnerable and not (hit and hit.ignore_iframes)) then return true end
  return PlayerStats.flag("invulnerable") and not (hit and hit.lethal)
end

function M.is_damage_invulnerable(self)
  return (self._damage_iframes_t or 0) > 0
end

-- Movement and parry iFrames or stat invulnerability, without post-hit
-- iFrames: the protection that return hazards pass over (hazard_return.lua).
function M.is_movement_invulnerable(self)
  return self._movement_iframes == true or PlayerStats.flag("invulnerable") == true
end

function M.exit_wall_climb(self)
  if self._on_wall or self._ledge_hanging or self._ledge_climbing then
    if self._cfg.debug_movement then
      pstate_log(string.format("%s WALL CLIMB EXIT: manual", self._cfg.debug_tag or "[PSTATE]"))
    end
    M.clear_ledge_state(self)
    self._on_wall = false
    self._wall_side = 0
    self._wall_time = 0
  end
end

function M.set_wall_contact(self, wall_side)
  -- A slam ignores wall attachment, including its momentum-stopping step.
  if self._pound_active or self._compact_active then return end
  -- Eight-direction dashes own velocity until their window ends. A vertical
  -- dash beside a wall must not reattach and lose its rise to wall climbing.
  -- Keep the legacy horizontal dash's wall-contact behavior unchanged.
  if (self._dash_t or 0) > 0 and self._last_dash_dir_y ~= nil then return end
  -- Ladder frames skip the normal wall-detach update. Clear incompatible wall
  -- state here so a nearby lip cannot attach wall-cling or reverse facing.
  if self._in_climb and not self._in_water then
    self._on_wall = false
    self._wall_side = 0
    self._wall_last_side = 0
    self._wall_time = 0
    Timers.clear_window(self, "_wall_contact_timer")
    Timers.clear_window(self, "_wall_coyote_t")
    self._wall_sliding = false
    M.clear_ledge_state(self)
    return
  end
  if wall_side ~= 0 then
    self._grapple_carry_t = 0
    if self._vertical_grid then self._vertical_grid.release_mult = nil end
    self._wall_jump_steering = nil
  end
  local WC = self._cfg.wall_climb
  -- Wall contact matters for wall climb OR wall jump (wall slide).
  local jump_only = WC and not WC.enabled and type(WC.wall_jump) == "table" and WC.wall_jump.enabled == true
  if not (WC and (WC.enabled or jump_only)) then
    return
  end
  -- The edge-climb path owns position kinematically; wall probes along the
  -- interpolation must not reattach the normal wall-climb state.
  if self._ledge_climbing then
    return
  end

  if wall_side ~= 0 and not self.grounded then
    local p = copy_player_position(self)
    local scale = tonumber(self._cfg.player_scale) or 1
    local offset = ColliderGeometry.BASE.main.offset_y * scale
      * (self._cfg.units_version == 1 and 1 / 1.75 or 1)
    local rule = WallSurfaces.find(p.x + wall_side * ((self.collider_half_width or self._cfg.collider_half_width or 30) + 2),
      p.y + offset, wall_side, self.collider_half_height or self._cfg.collider_half_height or 60)
    self._wall_rule, self._wall_last_rule = rule, rule
    local required = rule and rule.require_ability
    local preset_required = rule and rule.preset_ability
    if (required and required ~= "" and required ~= "none" and not Abilities.is_ability_unlocked(required))
      or (preset_required and preset_required ~= "" and preset_required ~= "none" and not Abilities.is_ability_unlocked(preset_required)) then
      M.clear_ledge_state(self)
      self._on_wall, self._wall_sliding = false, false
      self._wall_side, self._wall_last_side = 0, 0
      Timers.clear_window(self, "_wall_contact_timer")
      Timers.clear_window(self, "_wall_coyote_t")
      return
    end
    if rule and (rule.allow_slide == false or rule.allow_climb == false) then
      M.clear_ledge_state(self)
      self._on_wall = false
      if rule.allow_slide == false or (WC.wall_jump and WC.wall_jump.enabled == false) then
        self._wall_sliding = false
        self._wall_side, self._wall_last_side = wall_side, wall_side
        Timers.start_window(self, "_wall_contact_timer", WC.contact_grace or 0.12)
        local WJ = WC.wall_jump or {}
        if (self._wall_reattach_lock_t or 0) <= 0 then
          Timers.start_window(self, "_wall_coyote_t", WJ.coyote_time or WJ.slide_coyote_time or 0.12)
        end
        return
      end
    end
    jump_only = jump_only or (rule and rule.allow_climb == false)
  end

  if self._ledge_hanging then
    if wall_side ~= 0 and not self.grounded then
      Timers.start_window(self, "_wall_contact_timer", (self._cfg.wall_climb.contact_grace or 0.12))
      self._wall_side = wall_side
      self._wall_last_side = wall_side
    elseif self.grounded then
      M.clear_ledge_state(self)
      self._on_wall = false
      self._wall_side = 0
      self._wall_time = 0
    end
    return
  end
  
  -- wall_side: -1 = left wall, 1 = right wall, 0 = no wall
  if wall_side ~= 0 and not self.grounded then
    -- Refresh contact grace window
    Timers.start_window(self, "_wall_contact_timer", (self._cfg.wall_climb.contact_grace or 0))
    self._wall_last_side = wall_side
    -- Start wall climbing immediately when touching wall in air (unless locked)
    if not self._on_wall and (self._wall_reattach_lock_t or 0) <= 0 then
      if self._cfg.debug_movement then
        pstate_log(string.format("%s WALL CLIMB START: side=%d", self._cfg.debug_tag or "[PSTATE]", wall_side))
      end
      self._on_wall = true
      self._wall_side = wall_side
      self._wall_time = 0
      if not jump_only and M.wall_can_climb(self) then
        -- Wall climb: stop all momentum when sticking to wall
        self.vx = 0
        self.vy = 0
        self._jump_cut_pending = nil
      end
    end
    -- Keep updating wall side (in case player moves between walls)
    self._wall_side = wall_side
    self._wall_last_side = wall_side
  else
    -- Clear wall contact only if grounded (detaching in update handles other cases)
    if self.grounded and self._on_wall then
      if self._cfg.debug_movement then
        pstate_log(string.format("%s WALL CLIMB END: grounded", self._cfg.debug_tag or "[PSTATE]"))
      end
      self._on_wall = false
      self._wall_side = 0
      self._wall_time = 0
    end
  end
end


local function shape_walk_speed_by_mode(self, raw)
  local mode = self._cfg.walk_speed_mode or "scaled"
  local is_fixed = (mode == "fixed") or (mode == hash("fixed"))
  if is_fixed then return (raw ~= 0) and Util.sign(raw) or 0 end
  return raw
end

local function update_ledge_hang(self, input)
  local wall_climb = self._cfg.wall_climb or {}
  local cfg = ledge_config(self)
  local move_x = input.move_x or 0
  local move_y = input.move_y or 0
  local away = input_is_away_from_wall(
    self._ledge_hang_side,
    move_x,
    wall_climb.detach_away_threshold or 0.20)

  if (self._wall_contact_timer or 0) <= 0 then
    M.release_ledge_hang(self, { down_input = 0 })
  elseif move_y < -0.8 then
    M.release_ledge_hang(self, { down_input = move_y })
  elseif input.jump_down and away then
    M.release_ledge_hang(self, { jump_away = true })
  elseif move_y >= (cfg.up_threshold or 0.6) or input.jump_down then
    M.start_ledge_climb(self)
  else
    -- A hang is fully kinematic: ignore gravity and ordinary wall-slide speed.
    self.vx, self.vy = 0, 0
    self.facing = self._ledge_hang_side
  end
end

function M.dash_allowed()
  return Abilities.use_allowed("dash")
end

-- Tick temporary iFrames and recompute the invulnerable flag they drive.
-- Returns whether slide iFrames are active, for the debug log.
function M.tick_iframes(self, dt)
  -- Separate countdowns start only on a successful movement request. Zero is
  -- the legacy whole-action window; neither immunity window can outlive its action.
  Timers.step_window(self, "_slide_iframes_t", dt)
  Timers.step_window(self, "_dash_iframes_t", dt)
  local slide_iframes = (self._cfg.slide and self._cfg.slide.iframes) and (self._slide_t or 0) > 0
    and ((self._cfg.slide.iframe_seconds or 0) == 0 or (self._slide_iframes_t or 0) > 0)
  local dash_iframes = (self._cfg.air_dash and self._cfg.air_dash.iframes) and (self._dash_t or 0) > 0
    and ((self._cfg.air_dash.iframe_seconds or 0) == 0 or (self._dash_iframes_t or 0) > 0)
  local backdash_iframes = (self._cfg.backdash and self._cfg.backdash.iframes) and (self._backdash_t or 0) > 0
  Timers.tick_combat_deadline(self, "_parry_iframes_t", dt)
  Timers.tick_combat_deadline(self, "_damage_iframes_t", dt)
  self._movement_iframes = (slide_iframes or dash_iframes or backdash_iframes
    or ((self._parry_iframes_t or 0) > 0)) and true or false
  self._invulnerable = self._movement_iframes or ((self._damage_iframes_t or 0) > 0)
  return slide_iframes
end

-- Keep the same direction for movement and animation on the last frame.
function M.tick_wall_jump_steering(self, dt)
  local steering = self._wall_jump_steering
  local active, travel = Timers.slice_window(steering, "remaining", dt)
  if not active then self._wall_jump_steering = nil end
  if active or travel > 0 then return steering.direction, travel end
end

-- update does not run while a zip line ride or loaded cannon owns motion.
-- Keep its iFrames and countdowns running without its movement or locks.
-- The dash timer is already zero there: a ride refuses a dash and loading ends one.
function M.tick_owned_timers(self, dt)
  M.interrupt_window_handoffs(self)
  self._vertical_grid = nil
  if self._wall_jump_steering then M.tick_wall_jump_steering(self, dt) end
  M.tick_iframes(self, dt)
  M.tick_action_clocks(self, dt)
  Timers.tick_window(self, "_coyote_t", dt)
  Timers.tick_window(self, "_jump_buffer_t", dt)
  Timers.tick_all(self, OWNED_TIMERS, dt)
end

function M.tick_action_clocks(self, dt)
  Timers.tick_window(self, "_pound_cool", dt)
  local _, _, pound_exit = Timers.step_window(self, "_pound_recovery_t", dt)
  Timers.tick_window(self, "_slide_cool", dt)
  Timers.tick_window(self, "_dash_cool", dt)
  M.tick_backdash_cooldown(self, dt)
  return pound_exit
end

function M.tick_backdash_cooldown(self, dt)
  Timers.tick_window(self, "_backdash_cool", dt)
end

-- Retire the old speed hold once another state supplies the velocity. Features
-- already tick their clocks in their motion hook. Swim and climb keep the
-- cooldown of an interrupted action running across subsequent traversal draws.
function M.update_motion_takeover(self, dt, traversal, ordinary_motion)
  local features = self._host and self._host.features
  local compact = features and features.compact_form
  -- Compact Form runs ordinary physics while its own burst supplies speed.
  -- When another state takes the body, end just the burst and its stat source.
  if not ordinary_motion and compact and ((compact.roll or 0) > 0 or self._compact_roll_exit) then
    require("mvtk.player.compact_form").end_roll(self)
  end
  self._vertical_grid = nil
  if self._movement_windows or self._compact_roll_exit then M.interrupt_window_handoffs(self) end
  local dash = (self._dash_t or 0) > 0
  local slide = (self._slide_t or 0) > 0
  local backdash = (self._backdash_t or 0) > 0
  if dash or slide or backdash then
    local windows = self._movement_windows or {}
    -- The flag is owned by the cooldown window and expires or resets with it.
    if dash and windows._dash_cool then windows._dash_cool.continue_during_traversal = true end
    if slide and windows._slide_cool then windows._slide_cool.continue_during_traversal = true end
    Timers.clear_window(self, "_dash_t")
    Timers.clear_window(self, "_slide_t")
    Timers.clear_window(self, "_backdash_t")
    Timers.clear_window(self, "_slide_recovery_t")
    Timers.clear_window(self, "_dash_iframes_t")
    Timers.clear_window(self, "_slide_iframes_t")
    self._last_dash_dir, self._last_dash_dir_y = 0, nil
    self._dash_vy, self._dash_vertical_exited = nil, nil
    local blink = features and features.blink
    if blink and (dash or slide) then blink.dashing, blink.sliding = false, false end
    if traversal and (self._stun_t or 0) <= 0 then self._control_locked = false end
    if dash and Audio and Audio.stop_sfx then Audio.stop_sfx("air_dash") end
  end
  -- Intangible Dash normally publishes after physics. A takeover delivered
  -- by message must also retire the lease before another message can hit.
  if features and features.intangible_dash and features.intangible_dash.invulnerable then
    require("mvtk.player.features.intangible_dash_feature").reset(self)
  end
  if traversal then
    local windows = self._movement_windows
    local dash_cool, slide_cool = windows and windows._dash_cool, windows and windows._slide_cool
    if dash_cool and dash_cool.continue_during_traversal then Timers.tick_window(self, "_dash_cool", dt) end
    if slide_cool and slide_cool.continue_during_traversal then Timers.tick_window(self, "_slide_cool", dt) end
    M.tick_backdash_cooldown(self, dt)
    M.tick_iframes(self, dt)
  elseif self._movement_iframes then
    -- Cannon loading can have cleared a motion clock since the last tick.
    M.tick_iframes(self, 0)
  end
end

M.reference_window_remaining = Timers.reference_remaining

function M.start_dash_animation_lock(self)
  Timers.start_window(self, "_anim_lock_t", self._anim_lock_t or 0)
end

function M.tick_animation_lock(self, dt)
  Timers.tick_window(self, "_anim_lock_t", dt)
end

-- Sample the conditions driven by the opening velocity once per step.
function M.sample_vertical(self, step, duration, input, release_g)
  local extended = self._cfg.extended_jump
  step.hang = false
  if not release_g and self._extended_jump_active and extended and extended.enabled
    and math.abs(self.vy) <= 100 and input and input.jump_held then
    if not self._extended_jump_bonus_applied then
      self.vy = self.vy + self._extended_jump_speed
      self._extended_jump_bonus_applied = true
      if self._cfg.debug_movement then
        pstate_log(string.format("%s Extended jump bonus at apex: vy=%.1f",
          self._cfg.debug_tag or "[PSTATE]", self.vy))
      end
    end
    if self._extended_jump_hang_time < (extended.hang_time or 0.15) then
      self._extended_jump_hang_time = self._extended_jump_hang_time + duration
      step.hang = true
    end
  end
  if self.vy <= 0 then
    if self._jump_cut_pending then self._jump_cut_pending = nil end
    if self._grapple_flight then self._grapple_flight = false end
  end
  step.vy, step.left, step.plan = self.vy, duration, nil
end

function M.vertical_forces(self, step, input, g, release_g, release_ready)
  local cfg, vy = self._cfg, step.vy
  local jump_held = input and input.jump_held
  local hang = step.hang and self._extended_jump_active and jump_held
  if release_g then
    g = release_g
  else
    if hang then g = g * 0.1 end
    if vy < 0 then g = g * (cfg.fall_gravity_mult or 1.0) end
    local apex = cfg.apex_hang_speed or 0
    if apex <= 0 then apex = cfg.apex_threshold_vy or 0 end
    if apex > 0 and math.abs(vy) <= apex and not hang then
      g = g * (cfg.apex_gravity_mult or 1.0)
    end
  end
  local fast_falling = vy <= 0 and input and (input.move_y or 0) < -(cfg.fast_fall_threshold or 0.5)
  if fast_falling then g = g * (cfg.fast_fall_mult or 1.0) end

  local glide = cfg.glide
  local glide_wanted = not self._pound_active and not release_g and glide and glide.enabled
    and not self.grounded and (not glide.require_jump_held or jump_held)
  if glide_wanted and vy < 0 and not fast_falling and not hang then
    g = g * (glide.gravity_mult or 0.22)
  end
  if not release_g and vy > 0 and input and not jump_held and release_ready
    and not self._extended_jump_active and not self._grapple_flight and not self._super_jump_rising then
    if cfg.variable_jump_mode ~= "cut" then
      g = g * (cfg.jump_release_gravity_mult or 1.0)
    elseif self._jump_cut_pending then
      self.vy = self.vy * (cfg.jump_cut_speed_mult or 0.4)
      self._jump_cut_pending = nil
      step.plan = nil
    end
  end

  -- Glide gravity and the glide cap deliberately have different guards.
  local cap = (CONFIG and CONFIG.physics and CONFIG.physics.max_fall_speed) or cfg.max_fall_speed
  local player_cap = cfg.max_fall_speed_px or 0
  if player_cap > 0 then cap = math.max(cap or -player_cap, -player_cap) end
  if cap then
    if fast_falling then cap = cap * (cfg.fast_fall_max_mult or 1) end
    cap = cap * PlayerStats.mult("max_fall_mult")
  end
  local swim_cap = self._in_water and cfg.swim and cfg.swim.enabled and (cfg.swim.max_fall_speed or 0)
  if swim_cap and swim_cap > 0 then cap = math.max(cap or -swim_cap, -swim_cap) end
  local glide_cap = glide_wanted and glide.max_fall_speed
  if glide_cap and glide_cap > 0 then cap = math.max(cap or -glide_cap, -glide_cap) end
  if self._wall_sliding then
    local wall_jump = (cfg.wall_climb and cfg.wall_climb.wall_jump) or {}
    local speed = tonumber(wall_jump.slide_fall_speed)
    if wall_jump.slide_fall_speed == nil then
      speed = 350 * (cfg.scale_movement == false and 1 or (cfg.player_scale or 1))
    end
    local multiplier = self._wall_rule and self._wall_rule.slide_speed
    if multiplier == 0 then speed = 0
    elseif speed and multiplier and multiplier > 0 then speed = speed * multiplier end
    if speed and (speed > 0 or multiplier == 0) then cap = math.max(cap or -speed, -speed) end
  end
  return g, cap
end

-- A reference clamp replaces the whole step's travel with travel at the
-- clamped speed. Predict it before moving any part of that step.
function M.vertical_plan(self, step, g, cap, lift, lift_cap)
  local v = self.vy
  local gravity_end = v + g * step.left
  local lifted_end, lift_accel, lift_capped = M.env_lift(gravity_end, g, step.left, lift, lift_cap)
  if lift_accel then self._jump_cut_pending = nil end
  lift_accel = lift_accel or 0
  if glide_debug_enabled() and not self.grounded and step.vy < 0 then
    glide_log(string.format("[GLIDE] step: vy=%.1f, gravity=%.1f, fall cap=%s",
      step.vy, g, tostring(cap)))
  end
  local finish = cap and math.max(lifted_end, cap) or lifted_end
  local plan = step.storage
  if not plan then plan = {}; step.storage = plan end
  plan.g, plan.cap, plan.lift, plan.lift_cap = g, cap, lift, lift_cap
  plan.start, plan.duration, plan.elapsed = v, step.left, 0
  plan.accel, plan.gradient = lift_accel, g + lift_accel
  plan.finish, plan.before_cap = finish, lifted_end
  plan.linear = lift_capped or finish ~= lifted_end
  return plan
end

function M.advance_vertical_piece(self, plan, dt, held_y)
  plan.elapsed = plan.elapsed + dt
  if plan.linear or plan.elapsed >= plan.duration - 1e-12 then
    self.vy = plan.finish
  else
    self.vy = (plan.start + plan.g * plan.elapsed) + plan.accel * plan.elapsed
  end
  if held_y ~= nil then return held_y * dt end
  local curve = plan.linear and 0 or -plan.gradient * dt * (dt - M.REFERENCE_STEP) / 2
  return self.vy * dt + curve
end

function M.update_vertical(self, input, dt, hold_remaining, frame_offset, grapple_remaining, held_y, reference_handoff)
  local h = M.REFERENCE_STEP
  local step = self._vertical_grid
  if not step then
    step = {left = 0}
    self._vertical_grid = step
  end
  if dt <= 0 then return 0 end
  local cfg = self._cfg
  local base_g = (cfg.gravity or -1200) * (self._gravity_mult or 1.0) * PlayerStats.mult("gravity_mult")
  if self._in_water and cfg.swim and cfg.swim.enabled then
    base_g = base_g * (cfg.swim.gravity_mult or 1.0)
  end
  local hold = cfg.jump_min_hold_time or 0
  local wait = 0
  if input and not input.jump_held and hold_remaining > 0 then
    wait = JumpMath.shortest_jump_release_time(hold, h) - (hold - hold_remaining) - (frame_offset or 0)
  end
  -- The fixed-rate engine delta is the single-precision representation of
  -- one reference step. Make one decision while using its real travel time.
  local reference_frame = step.left == 0 and (reference_handoff or math.abs(dt - h) <= 1e-9)
  local remaining, travel = dt, 0
  local _, opening_bias = SurfaceEffects.at(self, 0)
  local bias = opening_bias
  while remaining > 1e-12 do
    local offset = (frame_offset or 0) + dt - remaining
    local _, next_bias, lift, lift_cap, contact_edge = SurfaceEffects.at(self, offset)
    if held_y == nil and bias ~= next_bias then
      self.vy = self.vy + bias - next_bias
      bias = next_bias
      step.left = 0
      self._surface_vertical_travel = true
    end
    if step.plan and (step.plan.lift ~= lift or step.plan.lift_cap ~= lift_cap) then
      step.left = 0
    end
    if step.left == 0 then
      if held_y ~= nil and remaining < dt then self.vy = held_y end
      if self._attack_vertical_sample then AttackExecutor.sample_attack_motion(self, offset) end
      local duration = reference_frame and dt or h
      local carry
      if grapple_remaining then
        carry = grapple_remaining - ((frame_offset or 0) + (dt - remaining) + duration)
        -- The reference checks the carry after spending the step. Treat
        -- authored frame multiples as spent despite countdown roundoff.
        if carry <= h * 1e-6 then carry = 0 end
      end
      step.release_mult = Grapple.release_gravity(self, 1, ACTIONS.grapple, cfg.grapple, carry)
      M.sample_vertical(self, step, duration, input, step.release_mult)
    end
    local piece = math.min(remaining, step.left)
    if contact_edge < piece - 1e-9 then piece = contact_edge end
    local ready = wait <= 1e-12
    if not ready and wait < piece and (not reference_frame or piece - wait > 1e-7) then
      piece = wait
    end
    local release_g = step.release_mult and base_g * step.release_mult
    local g, cap = M.vertical_forces(self, step, input, base_g, release_g, ready)
    local plan = step.plan
    if not plan or g ~= plan.g or cap ~= plan.cap or lift ~= plan.lift or lift_cap ~= plan.lift_cap then
      plan = M.vertical_plan(self, step, g, cap, lift, lift_cap)
      step.plan = plan
    end
    local piece_travel = M.advance_vertical_piece(self, plan, piece, held_y)
    -- At the reference rate the floor has already stopped the downward
    -- motion before the first lift interval. Preserve that boundary when
    -- the last grounded interval and the first lift share one display draw.
    if self.grounded and self.vy < 0 and contact_edge < remaining - 1e-9
      and math.abs(piece - contact_edge) < 1e-9 then
      local _, _, next_lift = SurfaceEffects.at(self, offset + piece)
      if next_lift > lift then
        self.vy = 0
        piece_travel = 0
      end
    end
    travel = travel + piece_travel
    if bias ~= opening_bias then travel = travel + (bias - opening_bias) * piece end
    step.left = step.left - piece
    remaining, wait = remaining - piece, wait - piece
    if step.left <= 1e-12 then
      step.left = 0
      if self._super_jump_rising and plan.before_cap <= 0 then self._super_jump_rising = false end
      if self._jump_cut_pending and self.vy <= 0 and (not self._extended_jump_active
        or self._extended_jump_bonus_applied or self.vy < -100) then
        self._jump_cut_pending = nil
      end
    end
  end
  step.last_vy, step.grounded = self.vy, self.grounded
  if bias ~= opening_bias then self.vy = self.vy + bias - opening_bias end
  return travel
end

function M.approach_horizontal_piece(self, dt, raw, carrying, stop_step)
  local reference_step = M.REFERENCE_STEP
  if raw ~= 0 then self.facing = Util.sign(raw) end
  local base = (self._run_gate and (self._cfg.run_speed or 2000) or (self._cfg.walk_speed or 1200))
  local shaped = shape_walk_speed_by_mode(self, raw)
  local speed_mult = PlayerStats.mult("speed_mult")
  local target_vx = base * shaped * speed_mult

  if self._cfg.debug_movement and (self._run_gate or raw ~= 0) then
    pstate_log(string.format("%s MOVEMENT: run_gate=%s, base_speed=%.0f, raw=%.3f, shaped=%.3f, target_vx=%.1f",
      self._cfg.debug_tag or "[PSTATE]", tostring(self._run_gate), base, raw, shaped, target_vx))
  end

  -- Choose accel/decel with air control multipliers and turn braking
  local on_ground = self.grounded
  local accel = (self._cfg.accel or 18)
  local decel = (self._cfg.decel or 26)
  local reversing = (target_vx ~= 0 and self.vx ~= 0 and Util.sign(target_vx) ~= Util.sign(self.vx))
  if on_ground then
    local run_accel = self._cfg.run_accel or 0
    if run_accel > 0 and not reversing then
      local speed = math.abs(self.vx)
      local walk_speed = (self._cfg.walk_speed or 1200) * speed_mult
      if speed >= walk_speed and math.abs(target_vx) > speed then accel = run_accel end
    end
    accel = accel * PlayerStats.mult("ground_accel_mult")
    decel = decel * PlayerStats.mult("ground_decel_mult")
  else
    accel = accel * (self._cfg.air_accel_mult or 1.0)
    decel = decel * (self._cfg.air_decel_mult or 1.0)
  end
  local turn_brake = (self._cfg.turn_brake_mult or 1.0)
  if on_ground then turn_brake = turn_brake * PlayerStats.mult("ground_turn_mult") end
  local slippery_reverse = on_ground and reversing and turn_brake < 0.9999
  if reversing and not slippery_reverse then decel = decel * turn_brake end

  local stop_epsilon = (self._cfg.stop_epsilon or 3.0)
  local move_target_vx = target_vx
  local coasting_reverse = false
  if slippery_reverse then
    -- Let slippery surfaces keep the current slide alive until momentum has
    -- bled down far enough for the new input direction to take over smoothly.
    local walk_speed = (self._cfg.walk_speed or 1200)
    local reverse_takeover_speed = math.max(
      stop_epsilon * 8,
      walk_speed * (0.08 + (0.20 * turn_brake))
    )
    if math.abs(self.vx) > reverse_takeover_speed then
      move_target_vx = 0
      coasting_reverse = true
    end
  end
  local accelerating = (math.abs(move_target_vx) > math.abs(self.vx))
  if coasting_reverse then accelerating = false end
  local rate = accelerating and accel or decel
  local carry_rate
  move_target_vx, carry_rate = Grapple.carry_steering(self, move_target_vx, accelerating,
    decel, ACTIONS.grapple, self._cfg.grapple, carrying)
  if carry_rate ~= nil then
    rate = carry_rate
    accelerating = false
  end
  local t = Util.clamp(rate * reference_step, 0, 1)
  -- Simple easing shaping for approach: >1 biases toward ease-out
  if accelerating then
    local e = (self._cfg.accel_ease_exp or 1.0)
    if e ~= 1.0 then t = 1 - math.pow(1 - t, e) end
  else
    local e = (self._cfg.decel_ease_exp or 1.0)
    if e ~= 1.0 then t = 1 - math.pow(1 - t, e) end
  end
  if carrying == nil then carrying = (self._grapple_carry_t or 0) > 0 end
  if stop_step and shaped == 0 and not carrying then
    local next_vx = Util.lerp(self.vx, move_target_vx, Timers.approach_fraction(t, stop_step))
    if math.abs(next_vx) <= stop_epsilon then
      self.vx = 0
      self._move_dx_correction = nil
      return
    end
  end
  if dt == reference_step then
    self.vx = Util.lerp(self.vx, move_target_vx, t)
  elseif dt > 0 then
    if t == 1 then
      self.vx = move_target_vx
    elseif t > 0 then
      local fraction, ratio = Timers.approach_fraction(t, dt)
      if fraction > 0 then
        local dx = Timers.approach_travel(self.vx, move_target_vx, t, dt, ratio)
        self.vx = Util.lerp(self.vx, move_target_vx, fraction)
        self._move_dx_correction = dx - self.vx * dt
      end
    end
  end
  if not stop_step and shaped == 0 and math.abs(self.vx) <= stop_epsilon and not carrying then
    self.vx = 0
    self._move_dx_correction = nil
  end
end

function M.approach_horizontal(self, dt, raw, carrying)
  if dt <= 0 or not SurfaceEffects.horizontal_active(self, raw) then
    return M.approach_horizontal_piece(self, dt, raw, carrying)
  end
  local initial = SurfaceEffects.at(self, 0)
  local offset = self._surface_horizontal_offset or 0
  local left, travel = dt, 0
  local world_vx = self.vx + initial
  while left > 1e-10 do
    local bias, _, _, _, to_contact_edge = SurfaceEffects.at(self, offset)
    local to_step_end = SurfaceEffects.horizontal_step(self, offset)
    local piece = math.min(left, to_contact_edge, to_step_end)
    self.vx = world_vx - bias
    self._move_dx_correction = nil
    M.approach_horizontal_piece(self, piece, raw, carrying, math.min(to_step_end, to_contact_edge))
    world_vx = self.vx + bias
    travel = travel + world_vx * piece + (self._move_dx_correction or 0)
    if bias ~= 0 then self._surface_horizontal_tail = true end
    offset, left = offset + piece, left - piece
  end
  if world_vx == 0 then self._surface_horizontal_tail = nil end
  self._surface_horizontal_offset = offset
  self.vx = world_vx - initial
  self._move_dx_correction = travel - world_vx * dt
end

function M.approach_with_pulse(self, dt, raw, pulse_dt, carrying)
  if pulse_dt > 0 and math.abs(raw) < 0.25 then
    local strength = (self._cfg.slide and self._cfg.slide.autorun_strength) or 0
    local nudged = math.max(-1, math.min(1, raw + (self._autorun_dir * strength)))
    M.approach_horizontal(self, pulse_dt, nudged, carrying)
    if pulse_dt < dt then
      local pulse_dx = self.vx * pulse_dt + (self._move_dx_correction or 0)
      self._move_dx_correction = nil
      M.approach_horizontal(self, dt - pulse_dt, raw, carrying)
      self._move_dx_correction = (self._move_dx_correction or 0) + pulse_dx - self.vx * pulse_dt
    end
  else
    M.approach_horizontal(self, dt, raw, carrying)
  end
end

function M.approach_after_launch_lock(self, dt, locked, raw, carry_dt)
  local elapsed, travel = 0, 0
  while elapsed < dt - 1e-12 do
    local steering_locked = elapsed < locked
    local carrying
    local ending = steering_locked and locked or dt
    if carry_dt ~= nil then
      carrying = elapsed < carry_dt
      if carrying then ending = math.min(ending, carry_dt) end
    end
    local piece = ending - elapsed
    self._move_dx_correction = nil
    M.approach_horizontal(self, piece, steering_locked and 0 or raw, carrying)
    travel = travel + self.vx * piece + (self._move_dx_correction or 0)
    elapsed = ending
  end
  self._move_dx_correction = travel - self.vx * dt
end

function M.stun_brake(self, dt)
  local decel = math.max(0, tonumber(self._hurt_decel) or tonumber(self._cfg.hurt_decel) or self._cfg.decel or 0)
  local epsilon = self._cfg.stop_epsilon or 3.0
  local h = M.REFERENCE_STEP
  if Timers.reference_frame(dt) and not self._stun_brake_step then
    local t = 1 - math.exp(-decel * dt)
    self.vx = Util.lerp(self.vx, 0, t)
    if math.abs(self.vx) <= epsilon then self.vx = 0 end
    return self.vx * dt
  end
  local fraction = 1 - math.exp(-decel * h)
  local left, dx = dt, 0
  while left > 1e-12 do
    local step = self._stun_brake_step
    if not step or step.vx ~= self.vx then
      step = {left = step and step.left or h}
      step.stop = math.abs(Util.lerp(self.vx, 0, 1 - math.exp(-decel * step.left))) <= epsilon
    end
    local piece = math.min(left, step.left)
    if step.stop then
      self.vx = 0
    else
      dx = dx + Timers.approach_travel(self.vx, 0, fraction, piece)
      self.vx = Util.lerp(self.vx, 0, 1 - math.exp(-decel * piece))
    end
    step.left, step.vx = step.left - piece, self.vx
    self._stun_brake_step = step.left > 1e-12 and step or nil
    left = left - piece
  end
  return dx
end

function M.tick_stun(self, dt)
  local remaining = Timers.window_remaining(self, "_stun_t")
  local expired = Timers.tick_deadline(self, "_stun_t", dt)
  -- The saved expiry update still locks controls, but no longer brakes.
  local travel = math.max(0, math.min(dt, remaining - M.REFERENCE_STEP))
  if Timers.reference_frame(dt) and not expired and dt - travel <= 1e-7 then return dt end
  return travel
end

function M.same_vertical_sample(self, step)
  if step.grounded ~= self.grounded then return false end
  if step.last_vy == self.vy then return true end
  if self._surface_reference_update or not self._surface_dt or not step.last_vy or not self.vy then return false end
  local _, bias_y = SurfaceEffects.at(self, 0)
  if bias_y == 0 or math.abs(step.last_vy - self.vy) > 1e-9 then return false end
  -- Subtracting and restoring a vertical speed bias can round by a few
  -- bits. That does not make the underlying motion a fresh gravity sample.
  self.vy = step.last_vy
  return true
end

function M.update(self, dt, input, bias_x, bias_y)
  self._move_dx_correction, self._move_dy_correction = nil, nil
  local launch_steer_dt, launch_steer_x = self._launch_steer_dt, self._launch_steer_x
  self._launch_steer_dt, self._launch_steer_x = nil, nil
  self._slide_exit_elapsed, self._dash_exit_elapsed = nil, nil
  local previous_grid = self._vertical_grid
  self._vertical_grid = nil
  local steering_direction, steering_travel
  if self._wall_jump_steering then
    steering_direction, steering_travel = M.tick_wall_jump_steering(self, dt)
  end
  if self._super_jump_rising or self._super_jump_started then
    if (self._dash_t or 0) > 0 or self._grapple_active
      or self._ledge_kinematic or self._ledge_hanging or self._ledge_climbing then
      self._super_jump_rising, self._super_jump_started = false, nil
    elseif self.vy <= 0 and (not previous_grid or previous_grid.left == 0
      or self.vy ~= previous_grid.last_vy) then
      self._super_jump_rising = false -- Keep the pending contact for a same-frame ceiling stop.
    end
  end
  if self.grounded or self._on_wall then
    self._grapple_carry_t = 0
    if previous_grid then previous_grid.release_mult = nil end
  end
  if input and (input.grapple_held == false or (input.grapple_held == nil and input.grapple_up)) then
    self._grapple_recast_t = 0
  else
    Timers.tick_window(self, "_grapple_recast_t", dt)
  end
  -- Keep a snapshot of the current input for edge-triggered actions
  self._last_input = input
  -- Update invulnerability based on slide/dash state and temporary iFrames
  local was_invulnerable = self._invulnerable
  local slide_iframes = M.tick_iframes(self, dt)
  
  if self._cfg.debug_movement and self._invulnerable ~= was_invulnerable then
    if self._invulnerable then
      local reason = slide_iframes and "slide" or "air dash"
      pstate_log(string.format("%s iFrames ENABLED (%s)", self._cfg.debug_tag or "[PSTATE]", reason))
    else
      pstate_log(string.format("%s iFrames DISABLED", self._cfg.debug_tag or "[PSTATE]"))
    end
  end
  
  -- timers
  local pound_exit = M.tick_action_clocks(self, dt)
  local horizontal_dt, stun_dt
  -- Runs after this frame's presses are queued and before they are used.
  if self._pound_active then drop_attacks_for_slam(self) end
  if (self._stun_t or 0) > 0 then
    stun_dt = M.tick_stun(self, dt)
    self._control_locked = true
  elseif self._control_locked
    and not self._grapple_active
    and not (self._super_jump_rising and (self._cfg.super_jump or {}).lock_horizontal ~= false)
    and not self._pound_active
    and (self._pound_recovery_t or 0) <= 0
    and (self._slide_t or 0) <= 0
    and (self._slide_recovery_t or 0) <= 0
    and (self._dash_t or 0) <= 0
    and (self._backdash_t or 0) <= 0 then
    -- release generic lock when not sliding/dashing
    self._control_locked = false
    if pound_exit then horizontal_dt = dt + pound_exit end
  end
  Timers.tick_window(self, "_coyote_t", dt)
  Timers.tick_window(self, "_jump_buffer_t", dt)
  local jump_hold_remaining = self._jump_hold_t or 0
  if (self._jump_hold_t or 0) > 0 then self._jump_hold_t = math.max(0, self._jump_hold_t - dt) end
  
  -- Extended jump logic
  if self._extended_jump_active then
    if input.jump_held then
      self._extended_jump_hold_time = (self._extended_jump_hold_time or 0) + dt
    else
      -- Jump button released, deactivate extended jump immediately
      local was_hanging = self._extended_jump_hang_time > 0
      self._extended_jump_active = false
      self._extended_jump_hang_time = 0  -- Stop hang time immediately
      if self._cfg.debug_movement then
        local msg = was_hanging and "Extended jump deactivated (button released) - hang time STOPPED" or "Extended jump deactivated (button released)"
        pstate_log(string.format("%s %s", self._cfg.debug_tag or "[PSTATE]", msg))
      end
    end
  end
  -- Wall timers
  Timers.tick_windows(self, WALL_TIMERS, dt)
  if self._on_wall then 
    self._wall_time = (self._wall_time or 0) + dt 
  end
  local vertical_dt, held_travel
  local exit_dx, exit_dy
  if self._compact_roll_exit then
    local roll_exit = self._compact_roll_exit
    horizontal_dt, exit_dx = dt + roll_exit.offset, roll_exit.dx
    self._compact_roll_exit = nil
  end
  if (self._slide_t or 0) > 0 then
    if self._cfg.debug_movement then
      pstate_log(string.format("%s SLIDE UPDATE: _slide_t=%.4f, dt=%.4f, new_slide_t=%.4f",
        self._cfg.debug_tag or "[PSTATE]", self._slide_t, dt, self._slide_t - dt))
    end
    local active, travel, offset = Timers.step_window(self, "_slide_t", dt)
    if active then
      held_travel = travel
    else
      if offset then
        horizontal_dt = dt + offset
        self._slide_exit_elapsed = horizontal_dt
        if self._control_locked and travel > 0 then exit_dx = self.vx * travel end
      end
      M.tick_iframes(self, 0) -- Drop movement immunity on this frame, preserving other windows.
      -- enter brief recovery/vulnerability window
      Timers.start_window(self, "_slide_recovery_t", (self._cfg.slide and self._cfg.slide.recovery) or 0, true, offset)
      self._control_locked = (self._slide_recovery_t or 0) > 0
      -- stop movement during recovery
      if self._control_locked then self.vx = 0 end
      if self._cfg.debug_movement then
        pstate_log(string.format("%s SLIDE ENDED: recovery_t=%.3f (cfg.recovery=%s), slide_held=%s",
          self._cfg.debug_tag or "[PSTATE]", self._slide_recovery_t, 
          tostring(self._cfg.slide and self._cfg.slide.recovery), 
          tostring(input and input.slide_held)))
      end
      
      -- If there's no recovery time, immediately check for run gate transition
      if self._slide_recovery_t == 0 then
        if self._cfg.slide_to_run and self._cfg.slide_to_run.enabled and self._cfg.slide_to_run.run_after_slide_when_held and input.slide_held and M.dash_allowed() then
          if self._cfg.debug_movement then
            pstate_log(string.format("%s No recovery time - enabling run gate immediately", self._cfg.debug_tag or "[PSTATE]"))
          end
          self._run_gate = true
          -- autorun nudge
          local SL = self._cfg.slide or {}
          Timers.start_window(self, "_autorun_nudge_t", SL.autorun_pulse or 0)
          local d = (self.facing ~= 0 and self.facing or (self.vx ~= 0 and (self.vx>0 and 1 or -1) or 1))
          self._autorun_dir = d
        else
          -- Ensure run gate is cleared if trigger is not held
          if self._cfg.debug_movement then
            pstate_log(string.format("%s No recovery time - clearing run gate (RT not held)", self._cfg.debug_tag or "[PSTATE]"))
          end
          self._run_gate = false
        end
      end
    end
  end
  if (self._slide_recovery_t or 0) > 0 then
    local active, _, offset = Timers.step_window(self, "_slide_recovery_t", dt)
    if not active then
      if offset then horizontal_dt = dt + offset end
      self._control_locked = false
      -- after recovery, optionally gate into run if still held
      if self._cfg.slide_to_run and self._cfg.slide_to_run.enabled and self._cfg.slide_to_run.run_after_slide_when_held and input.slide_held and M.dash_allowed() then
        if self._cfg.debug_movement then
          pstate_log(string.format("%s Slide recovery complete, slide still held - enabling run gate", self._cfg.debug_tag or "[PSTATE]"))
        end
        self._run_gate = true
        -- autorun nudge
        local SL = self._cfg.slide or {}
        Timers.start_window(self, "_autorun_nudge_t", SL.autorun_pulse or 0)
        local d = (self.facing ~= 0 and self.facing or (self.vx ~= 0 and (self.vx>0 and 1 or -1) or 1))
        self._autorun_dir = d
      else
        -- Ensure run gate is cleared if trigger is not held after recovery
        if self._cfg.debug_movement then
          pstate_log(string.format("%s Slide recovery complete, RT not held - clearing run gate", self._cfg.debug_tag or "[PSTATE]"))
        end
        self._run_gate = false
      end
    end
  end
  local dash_damping, dash_before_exit, dash_held_y, exact_dash_y
  if (self._dash_t or 0) > 0 then
    local window = self._movement_windows and self._movement_windows._dash_t
    local directional = self._last_dash_dir_y ~= nil and not self._dash_vertical_exited
    local dash_edge = directional and window and window.visible == self._dash_t and window.length - window.elapsed
    if dash_edge then
      local h = M.REFERENCE_STEP
      local edge_on_grid = math.abs(dash_edge - math.floor(dash_edge / h + 0.5) * h) < 1e-7
      exact_dash_y = math.abs(dt - h) > 1e-9 or not edge_on_grid
      if exact_dash_y and dash_edge < dt - 1e-12 then
        dash_damping = self._cfg.air_dash.end_vertical_speed_mult or 0.35
        dash_before_exit = math.max(0, dash_edge)
        dash_held_y = self._dash_vy
        self._dash_vertical_exited = true
      end
    end
    local active, travel, offset = Timers.step_window(self, "_dash_t", dt)
    if active then
      held_travel = travel
    else
      if offset then
        horizontal_dt = dt + offset
        local legacy_held_y = not exact_dash_y and not self._dash_vertical_exited and self._dash_vy
        if legacy_held_y then vertical_dt = horizontal_dt end
        self._dash_exit_elapsed = horizontal_dt
        if travel > 0 then
          if self._control_locked then exit_dx = self.vx * travel end
          if legacy_held_y then exit_dy = legacy_held_y * travel end
        end
      end
      M.tick_iframes(self, 0)
      if self._last_dash_dir_y ~= nil and not self._dash_vertical_exited then
        self._jump_cut_pending = nil
        if self._dash_vy == nil then
          dash_damping = self._cfg.air_dash.end_vertical_speed_mult or 0.35
        else
          self.vy = self.vy * (self._cfg.air_dash.end_vertical_speed_mult or 0.35)
          previous_grid = nil
        end
      end
      self._dash_vertical_exited = nil
      self._dash_vy = nil
      self._last_dash_dir_y = nil
      self._control_locked = false
      self._last_dash_dir = 0
      if Audio and Audio.stop_sfx then
        Audio.stop_sfx("air_dash")
      end
    end
  end
  -- Decrement double jump animation timer
  if (self._double_jump_t or 0) > 0 then
    self._double_jump_t = math.max(0, self._double_jump_t - dt)
  end
  if (self._backdash_t or 0) > 0 then
    local active, travel = Timers.step_held_speed(self, "_backdash_t", dt)
    if active then
      held_travel = travel
    else
      if travel > 0 then
        horizontal_dt = dt - travel
        if self._control_locked then exit_dx = self.vx * travel end
      end
      self._control_locked = false
    end
  end

  if self._cfg.slide_to_run and self._cfg.slide_to_run.enabled and not M.dash_allowed() then
    self._run_gate = false
    Timers.start_window(self, "_autorun_nudge_t", 0)
  end
  if self._cfg.slide_to_run and self._cfg.slide_to_run.enabled and self._cfg.slide_to_run.clear_run_on_release and not input.slide_held then
    if self._cfg.debug_movement and self._run_gate then
      pstate_log(string.format("%s CLEARING RUN GATE: slide released (slide_held=%s)",
        self._cfg.debug_tag or "[PSTATE]", tostring(input.slide_held)))
    end
    self._run_gate = false
  end
  local neutral = self._cfg.walk_stop_deadzone or 0.2
  if math.abs(input.move_x or 0) <= neutral and math.abs(self.vx) < (self._cfg.stop_epsilon or 3.0) and not input.slide_held then
    if self._cfg.debug_movement and self._run_gate then
      pstate_log(string.format("%s CLEARING RUN GATE: Neutral stick + slide not held (move_x=%.3f, vx=%.1f, slide_held=%s)",
        self._cfg.debug_tag or "[PSTATE]", input.move_x or 0, self.vx, tostring(input.slide_held)))
    end
    self._run_gate = false
  end

  -- Grapple owns velocity through the ordinary collision integrator. Running
  -- normal air steering/gravity afterward used to overwrite every pull.
  validate_grapple(self, input)
  self._grapple_bias_x, self._grapple_bias_y = bias_x, bias_y
  local grapple_motion, release_travel, release_dx, release_dy =
    Grapple.update(self, dt, input, ACTIONS.grapple, self._cfg.grapple)
  self._grapple_bias_x, self._grapple_bias_y = nil, nil
  if grapple_motion then return end
  local cannon_offset = self._launch_fire_offset
  self._launch_fire_offset = nil
  if cannon_offset then
    release_travel, release_dx, release_dy = cannon_offset, 0, 0
  end
  release_travel = release_travel or self._zipline_release_travel
  self._zipline_release_travel = nil
  if release_travel then
    horizontal_dt, vertical_dt = dt - release_travel, dt - release_travel
    exit_dx, exit_dy = release_dx or self.vx * release_travel, release_dy or self.vy * release_travel
  end

  -- Kinematic ledge movement takes priority over wall movement, gravity and
  -- horizontal input. player.script consumes the public transition flags for
  -- Edge_Idle/Edge_Climb animation selection.
  if self._ledge_climbing then
    advance_ledge_climb(self, dt)
    return
  elseif self._ledge_hanging then
    update_ledge_hang(self, input)
    return
  end

  -- Wall climbing movement - COMPLETELY OVERRIDE GRAVITY AND MOVEMENT
  if not self._pound_active and self._on_wall and self._cfg.wall_climb and self._cfg.wall_climb.enabled and M.wall_can_climb(self) then
    local climb_input = input.move_y or 0
    local move_x = input.move_x or 0
    local stick_speed = self._cfg.wall_climb.stick_speed or 0
    local climb_speed = self._cfg.wall_climb.climb_speed or 800
    local toward_required = self._cfg.wall_climb.require_input_toward
    local toward_thresh = self._cfg.wall_climb.input_threshold or 0.25
    local away_thresh = self._cfg.wall_climb.detach_away_threshold or 0.20
    local LC = ledge_config(self)

    -- The normal wall solver already snapped us flush. Probe its centre and
    -- +0.5 samples to recognize the first frame where the wall ends at a lip.
    if animated_ledge_hang_enabled(self, LC) then
      local is_lip, center_hit = BonePhysics.probe_ledge_lip(self, self._wall_side)
      if is_lip and M.enter_ledge_hang(self, self._wall_side, center_hit) then
        update_ledge_hang(self, input)
        return
      end
    end

    -- Detach if we lost contact grace
    if (self._wall_contact_timer or 0) <= 0 then
      if self._cfg.debug_movement then
        pstate_log(string.format("%s WALL CLIMB END: contact grace expired", self._cfg.debug_tag or "[PSTATE]"))
      end
      self._on_wall = false
      self._wall_side = 0
      self._wall_time = 0
      -- start wall coyote to allow late wall jump
      local WJ = self._cfg.wall_climb.wall_jump or {}
      Timers.start_window(self, "_wall_coyote_t", WJ.coyote_time or 0)
      -- continue with normal movement
    else
      -- Require holding toward the wall to remain attached
      if toward_required then
        local holding_toward = (self._wall_side < 0 and move_x <= -toward_thresh) or (self._wall_side > 0 and move_x >= toward_thresh)
        if not holding_toward then
          -- Not holding toward; start coyote and drop
          if self._cfg.debug_movement then
            pstate_log(string.format("%s WALL CLIMB END: not holding toward (move_x=%.2f)", self._cfg.debug_tag or "[PSTATE]", move_x))
          end
          self._on_wall = false
          self._wall_side = 0
          local WJ = self._cfg.wall_climb.wall_jump or {}
          Timers.start_window(self, "_wall_coyote_t", WJ.coyote_time or 0)
          -- fall through to normal movement
        end
      end
    end

    if self._on_wall then
      local side = self._wall_side or 0
      local holding_away = side ~= 0 and (
        (side < 0 and move_x >= away_thresh)
        or (side > 0 and move_x <= -away_thresh)
      )
      if holding_away then
        local WJ = self._cfg.wall_climb.wall_jump or {}
        if self._cfg.debug_movement then
          pstate_log(string.format("%s WALL CLIMB END: pushed away (side=%d, move_x=%.2f)",
            self._cfg.debug_tag or "[PSTATE]", side, move_x))
        end
        self._on_wall = false
        self._wall_side = 0
        self._wall_time = 0
        self.vx = -side * (self._cfg.wall_climb.detach_push or 220)
        Timers.start_window(self, "_wall_coyote_t", WJ.coyote_time or 0)
        Timers.start_window(self, "_wall_reattach_lock_t", self._cfg.wall_climb.reattach_lock or (WJ.reattach_lock or 0.18))
      end
    end
    
    if self._on_wall then
      -- Legacy up+jump teleport remains the compatibility path whenever hang
      -- animations are disabled or unavailable for the active renderer.
      if LC.enabled
        and not animated_ledge_hang_enabled(self, LC)
        and input and input.jump_down
        and climb_input >= (LC.up_threshold or 0.6)
      then
        instant_ledge_climb(self, LC)
        return
      end

      -- STICK TO THE WALL - no horizontal movement at all
      self.vx = 0
      self._jump_cut_pending = nil
    
      -- Direct control of vertical movement with left stick
      if math.abs(climb_input) > 0.1 then
        -- Direct control - up/down based on stick input
        self.vy = climb_speed * climb_input
        if self._cfg.debug_movement then
          pstate_log(string.format("%s Wall climb: input=%.2f, vy=%.1f", 
            self._cfg.debug_tag or "[PSTATE]", climb_input, self.vy))
        end
        
        -- If climbing down fast, allow falling off the wall
        if climb_input < -0.8 then
          local WJ = self._cfg.wall_climb.wall_jump or {}
          self._on_wall = false
          self._wall_side = 0
          Timers.start_window(self, "_wall_coyote_t", WJ.coyote_time or 0)
          return  -- Let gravity take over
        end
      else
        -- Neutral stick - stick to wall (no movement)
        if stick_speed > 0 then
          -- Slow slide down if configured
          self.vy = -stick_speed
        else
          -- Perfect stick - no movement at all
          self.vy = 0
        end
      end
      
      -- Skip all gravity and normal movement when wall climbing
      return
    end
  end

  -- Wall slide: wall jump unlocked without wall climb. Hold toward the wall to
  -- slide down it (fall speed capped after gravity below); release, land or
  -- lose contact to detach, with a short coyote window for a late wall jump.
  self._wall_sliding = false
  if not self._pound_active and self._on_wall and self._cfg.wall_climb and (not self._cfg.wall_climb.enabled or not M.wall_can_climb(self)) then
    local WC = self._cfg.wall_climb
    local WJ = WC.wall_jump or {}
    local move_x = input.move_x or 0
    local side = self._wall_side or 0
    local thresh = WC.input_threshold or 0.25
    local holding_toward = (side < 0 and move_x <= -thresh) or (side > 0 and move_x >= thresh)
    if self.grounded or (self._wall_contact_timer or 0) <= 0 or not holding_toward then
      self._on_wall = false
      self._wall_side = 0
      self._wall_time = 0
      Timers.start_window(self, "_wall_coyote_t", WJ.slide_coyote_time or 0.12)
    else
      self._wall_sliding = true
      self.vx = 0
    end
  end

  -- Horizontal
  local grapple_remaining
  local frame_dt = dt
  dt = horizontal_dt or frame_dt
  -- While an action locks movement, keep its imposed velocity.
  if self._super_jump_rising and (self._cfg.super_jump or {}).lock_horizontal ~= false then
    self.vx = 0
  elseif self._control_locked and ((self._slide_t or 0) > 0 or (self._dash_t or 0) > 0 or (self._slide_recovery_t or 0) > 0 or (self._backdash_t or 0) > 0 or self._pound_active or (self._pound_recovery_t or 0) > 0) then
    if self.vx ~= 0 then self.facing = Util.sign(self.vx) end
    if held_travel and held_travel ~= frame_dt then self._move_dx_correction = self.vx * (held_travel - frame_dt) end
  elseif stun_dt and stun_dt >= dt - 1e-12 and stun_dt > 0 then
    local dx = M.stun_brake(self, dt)
    if dx ~= self.vx * dt then self._move_dx_correction = dx - self.vx * dt end
  elseif not self._on_wall or (stun_dt or 0) > 0 then
    local stun_dx
    if stun_dt and stun_dt > 0 then
      stun_dx = M.stun_brake(self, stun_dt)
      dt = dt - stun_dt
    end
    self._stun_brake_step = nil
    local raw = input.move_x or 0
    local pulse_dt = Timers.consume_pulse(self, "_autorun_nudge_t", dt, frame_dt)
    local forced = math.min(steering_travel or 0, dt)
    grapple_remaining = Timers.window_remaining(self, "_grapple_carry_t")
    local carry_dt
    if Timers.has_window(self, "_grapple_carry_t") then
      local _, travel = Timers.tick_deadline(self, "_grapple_carry_t", frame_dt - (release_travel or 0))
      local tolerance = Timers.reference_frame(frame_dt) and 1e-7 or 1e-12
      if math.abs(travel - dt) <= tolerance then travel = dt end
      carry_dt = math.min(dt, travel)
    end
    if steering_direction and forced == dt then
      M.approach_horizontal(self, dt, steering_direction)
    elseif forced > 0 then
      M.approach_horizontal(self, forced, steering_direction)
      local forced_dx = self.vx * forced + (self._move_dx_correction or 0)
      self._move_dx_correction = nil
      M.approach_with_pulse(self, dt - forced, raw, pulse_dt - forced)
      self._move_dx_correction = (self._move_dx_correction or 0) + forced_dx - self.vx * forced
    elseif launch_steer_dt and launch_steer_dt < dt then
      M.approach_after_launch_lock(self, dt, launch_steer_dt, launch_steer_x, carry_dt)
    elseif carry_dt and carry_dt < dt then
      local carry_dx = 0
      if carry_dt > 0 then
        M.approach_with_pulse(self, carry_dt, raw, math.min(pulse_dt, carry_dt), true)
        carry_dx = self.vx * carry_dt + (self._move_dx_correction or 0)
        self._move_dx_correction = nil
      end
      M.approach_with_pulse(self, dt - carry_dt, raw, pulse_dt - carry_dt, false)
      self._move_dx_correction = (self._move_dx_correction or 0) + carry_dx - self.vx * carry_dt
    else
      M.approach_with_pulse(self, dt, raw, pulse_dt, carry_dt and true or nil)
    end
    if not carry_dt then self._grapple_carry_t = math.max(0, grapple_remaining - frame_dt) end
    if stun_dx then exit_dx = (exit_dx or 0) + stun_dx end
  end
  if dt ~= frame_dt or exit_dx then
    self._move_dx_correction = (self._move_dx_correction or 0) + self.vx * (dt - frame_dt) + (exit_dx or 0)
  end

  -- Same-speed contact transitions and skipped gravity updates can
  -- invalidate the sample even when the numerical velocity did not change.
  if previous_grid then
    if not M.same_vertical_sample(self, previous_grid) then previous_grid.left = 0 end
    self._vertical_grid = previous_grid
  end
  local held_y = (self._dash_t or 0) > 0 and not self._dash_vertical_exited and self._dash_vy
  local dy
  if dash_damping then
    local before_exit = math.max(0, dash_before_exit or 0)
    if before_exit > 0 then
      if dash_held_y ~= nil then
        dy = M.update_vertical(self, input, before_exit, jump_hold_remaining, 0, grapple_remaining, dash_held_y)
        self.vy = dash_held_y
      else
        dy = M.update_vertical(self, input, before_exit, jump_hold_remaining, 0, grapple_remaining)
      end
    end
    self._jump_cut_pending = nil
    self.vy = self.vy * dash_damping
    self._vertical_grid = nil
    dy = (dy or 0) + M.update_vertical(self, input, frame_dt - before_exit, jump_hold_remaining, before_exit, grapple_remaining)
  else
    local motion_dt = vertical_dt or frame_dt
    -- A native-rate paused dash can hand back several nanoseconds of
    -- previously trimmed travel. It still spends one reference decision.
    local reference_handoff = not cannon_offset and vertical_dt ~= nil and math.abs(frame_dt - M.REFERENCE_STEP) <= 1e-9
    dy = M.update_vertical(self, input, motion_dt, jump_hold_remaining, frame_dt - motion_dt,
      grapple_remaining and grapple_remaining + (release_travel or 0), held_y or nil, reference_handoff)
  end
  if held_y then
    self._jump_cut_pending = nil
    self.vy = held_y
    if self._vertical_grid then self._vertical_grid.last_vy = held_y end
    self._move_dy_correction = not exact_dash_y and held_travel and held_travel ~= frame_dt
      and held_y * (held_travel - frame_dt) or nil
  elseif self.vy * frame_dt ~= dy or exit_dy then
    self._move_dy_correction = dy - self.vy * frame_dt + (exit_dy or 0)
  end

  -- If a jump is buffered and we regain a valid jump window (ground or coyote), consume it
  if not self._pound_active and (self._jump_buffer_t or 0) > 0 and (self.grounded or (self._coyote_t or 0) > 0) then
    self._vertical_grid = nil
    self.vy = M.ground_jump_velocity(self)
    self._move_dy_correction = nil
    self._jump_cut_pending = true
    self.grounded = false
    Timers.clear_window(self, "_coyote_t")
    Timers.clear_window(self, "_jump_buffer_t")
    self._jump_hold_t = self._cfg.jump_min_hold_time or 0
  end

  -- HUD: report current movement mode to UI (only when it changes)
  local mode
  if (self._dash_t or 0) > 0 then
    mode = "Air Dash"
  elseif (self._backdash_t or 0) > 0 then
    mode = "Backdash"
  elseif (self._slide_t or 0) > 0 then
    mode = "Slide"
  elseif (self._slide_recovery_t or 0) > 0 then
    mode = "Recovery"
  elseif self._compact_active then
    mode = self._compact_mode_text
  elseif self._on_wall then
    mode = "Wall Climb"
  elseif self._extended_jump_active and self._extended_jump_hang_time > 0 then
    mode = "Extended Jump"
  elseif self._in_water then
    mode = "Swim"
  elseif self._run_gate then
    mode = "Run"
  else
    mode = "Walk"
  end
  if mode ~= self._last_mode then
    self._last_mode = mode
    pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_mode"), { mode = mode })
  end
end

-- Recoil replaces movement on the affected axes: running into a hit must not
-- overpower the attacker-directed kick. A zero axis preserves existing motion.
function M.apply_knockback(self, kx, ky)
  M.cancel_ground_pound(self)
  if (kx and kx ~= 0) or (ky and ky ~= 0) then M.interrupt_window_handoffs(self) end
  if kx and kx ~= 0 then self.vx = kx end
  if ky and ky ~= 0 then
    self._vertical_grid = nil
    self.vy = ky
    self._jump_cut_pending = nil
  end
end

-- Lock controls briefly to simulate hit-stun
function M.apply_stun(self, t)
  local tt = tonumber(t) or 0
  if tt > 0 then
    M.interrupt_window_handoffs(self)
    self._wall_jump_steering = nil
    M.cancel_ground_pound(self)
    Grapple.clear(self)
    Timers.extend_window(self, "_stun_t", tt)
    self._stun_brake_step = nil
    self._control_locked = true
  end
end

-- Grant temporary invulnerability (e.g., after a successful parry)
function M.add_iframes(self, t)
  local tt = tonumber(t) or 0
  if tt > (self._parry_iframes_t or 0) then
    Timers.start_combat_window(self, "_parry_iframes_t", tt)
    -- Damage messages can arrive back-to-back before the next movement tick.
    self._movement_iframes, self._invulnerable = true, true
  end
end

function M.add_damage_iframes(self)
  Timers.start_combat_window(self, "_damage_iframes_t", self._damage_iframes_duration or 0.8)
end

return M
