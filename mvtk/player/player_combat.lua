-- mvtk/player/player_combat.lua
-- Combat and movement-contact action helpers extracted from player.script.

local SpineVisual = require "mvtk.player.spine_visual"
local PlayerStats = require "mvtk.player.player_stats"

local PlayerElements = require "mvtk.combat.player_elements"

local M = {}

local ACTIONS = {}
local HITBOX_CONFIG = {}
local C
local BoneCollision
local CombatConfig
local ParrySystem
local PSTATE
local AttackExecutor
local SPINE_MIX_BLEND_REPLACE
local _Audio

local player_log = function() end
local anim_attack = function() end
local anim_once = function() end
local anim_overlay_once = function() end
local anim_set = function() end
local play_sfx = function() end
local can_consume_ability = function() return true end
local consume_ability = function() return true end
local resolve_attack_type = function() return nil end
local number_or_default = function(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return n
end
local movement_action_direction = function() return 1 end
local resolve_movement_contact_config = function() return nil end

function M.configure(opts)
  opts = opts or {}
  ACTIONS = opts.ACTIONS or ACTIONS
  HITBOX_CONFIG = opts.HITBOX_CONFIG or HITBOX_CONFIG
  C = opts.C or C
  BoneCollision = opts.BoneCollision or BoneCollision
  CombatConfig = opts.CombatConfig or CombatConfig
  ParrySystem = opts.ParrySystem or ParrySystem
  PSTATE = opts.PSTATE or PSTATE
  AttackExecutor = opts.AttackExecutor or AttackExecutor
  SPINE_MIX_BLEND_REPLACE = opts.SPINE_MIX_BLEND_REPLACE or SPINE_MIX_BLEND_REPLACE
  _Audio = opts.Audio or _Audio

  player_log = opts.player_log or player_log
  anim_attack = opts.anim_attack or anim_attack
  anim_once = opts.anim_once or anim_once
  anim_overlay_once = opts.anim_overlay_once or anim_overlay_once
  anim_set = opts.anim_set or anim_set
  play_sfx = opts.play_sfx or play_sfx
  can_consume_ability = opts.can_consume_ability or can_consume_ability
  consume_ability = opts.consume_ability or consume_ability
  resolve_attack_type = opts.resolve_attack_type or resolve_attack_type
  number_or_default = opts.number_or_default or number_or_default
  movement_action_direction = opts.movement_action_direction or movement_action_direction
  resolve_movement_contact_config = opts.resolve_movement_contact_config or resolve_movement_contact_config
end

-- Keep the physical hold separate from the press buffer's legacy hold clock.
-- A buffered charged attack consumes this hold too, so release cannot pay twice.
function M.update_charge(self, dt, input)
  self._light_charge_release_t = nil
  if require("mvtk.player.hold_toggles").sync(self, "charged_slash")
    or self._is_dead or (self._stun_t or 0) > 0 then
    self._light_hold_t = 0
    self._light_charge_t = nil
    return
  end
  if input.light_down then self._light_charge_t = 0 end
  if input.light_held then
    self._light_hold_t = (self._light_hold_t or 0) + dt
    if self._light_charge_t ~= nil then self._light_charge_t = self._light_charge_t + dt end
  elseif input.light_up then
    self._light_charge_release_t = self._light_charge_t
    self._light_charge_t = nil
    self._light_hold_t = 0
  else
    self._light_charge_t = nil
    self._light_hold_t = 0
  end
end

function M.process_charge_release(self, input, cancelled)
  local charge_t = self._light_charge_release_t
  self._light_charge_release_t = nil -- A release is one attempt, never a buffered press.
  if cancelled then self._light_charge_t = nil; self._light_hold_t = 0; return end
  if charge_t == nil then return end
  local CA = ACTIONS.charge_attack or {}
  if not CA.enabled or not can_consume_ability("charge_attack") then return end
  local executor = AttackExecutor or require "mvtk.combat.attack_executor"
  -- request(light) can queue a normal combo while busy; a charged release must
  -- only start its actual variant, never queue/pay for that normal follow-up.
  if executor.is_active(self) then return end
  local config = CombatConfig or require "mvtk.combat.config"
  local ctx = require("mvtk.player.combat_input").attack_intent(self, input, config.get(), charge_t)
  if not ctx.want_charged then return end
  local attack_set = config.resolve_attack_set()
  local bucket = attack_set.grounded or attack_set.default or {}
  if not bucket.charged then return end
  if executor.request(self, "light", ctx) then
    consume_ability("charge_attack")
    pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_cooldown"), { action = "charged" })
  end
end

function M.process_melee_intents(self, input, interacted_this_frame, stunned)
  M.process_charge_release(self, input, interacted_this_frame or stunned or self._is_dead)
  local AttackExecutor = AttackExecutor or require "mvtk.combat.attack_executor"
  -- Process light attack after interact priority has had a chance to consume the same press.
  local want_light = (self._light_buffer_count or 0) > 0
  if want_light and not interacted_this_frame and not stunned then
    local ds = ACTIONS.down_strike or {}
    local ds_enabled = ds.enabled and can_consume_ability("down_strike")
    local CA = ACTIONS.charge_attack or {}
    local ca_enabled = CA.enabled and can_consume_ability("charge_attack")
    local cfg = (CombatConfig or require("mvtk.combat.config")).get()
    local ctx = require("mvtk.player.combat_input").attack_intent(self, input, cfg)
    local wants_down_strike = ctx.want_down_strike and ds_enabled
    local wants_charged = ctx.want_charged and ca_enabled
    ctx.want_down_strike, ctx.want_charged = wants_down_strike, wants_charged
    local requested = AttackExecutor.request(self, "light", ctx)
    if requested then
      self._light_buffer_count = (self._light_buffer_count or 1) - 1  -- Consume one queued press
      self._light_hold_t = 0
      if wants_down_strike then
        consume_ability("down_strike")
        pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_cooldown"), { action = "down" })
      elseif wants_charged then
        self._light_charge_t = nil
        consume_ability("charge_attack")
        pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_cooldown"), { action = "charged" })
      else
        pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_cooldown"), { action = "light" })
      end
    end
  end

  -- Process heavy attack (check queue OR immediate press)
  local want_heavy = (self._heavy_buffer_count or 0) > 0
  if want_heavy and not interacted_this_frame and not stunned then
    local cfg = (CombatConfig or require("mvtk.combat.config")).get()
    local ctx = require("mvtk.player.combat_input").attack_intent(self, input, cfg)
    local requested = AttackExecutor.request(self, "heavy", ctx)
    if requested then
      self._heavy_buffer_count = (self._heavy_buffer_count or 1) - 1
      pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_cooldown"), { action = "heavy" })
    end
  end
end

function M.process_ranged_intent(self, input, stunned)
  local AttackExecutor = AttackExecutor or require "mvtk.combat.attack_executor"
  local stance = self._host and self._host.features.aim_stance
  if stance and (stance.active or stance.released) then
    -- Physics can leave the ground or attach to a climb after pre_physics.
    local cfg = (CombatConfig or require("mvtk.combat.config")).get()
    if stunned or not self.grounded or self._compact_active or self._in_climb or self._on_wall
      or self._ledge_hanging or self._ledge_climbing or self._ledge_kinematic or not (cfg.aim or {}).stance then
      require("mvtk.player.features.aim_stance_feature").reset(self)
      return
    end
    if stance.active then return end -- Keep the press-time buffer until release.
  end
  -- Process ranged attack (check queue OR immediate press)
  local want_ranged = (self._ranged_buffer_count or 0) > 0
  if stance and not want_ranged then stance.released = false end
  if want_ranged and not stunned and can_consume_ability("ranged_attack") then
    local cfg = (CombatConfig or require("mvtk.combat.config")).get()
    -- Release-frame movement can turn the player after the stance hook. Neutral
    -- and facing-only shots must retain the held pose just like directional aim.
    if stance and stance.released then self.facing = stance.facing or self.facing end
    local ctx = require("mvtk.player.combat_input").attack_intent(self,
      stance and stance.released and { move_x = stance.x, move_y = stance.y } or input, cfg)
    ctx.aim = { x = ctx.aim_x, y = ctx.aim_y, mode = (cfg.aim or {}).mode }
    local requested = AttackExecutor.request(self, "ranged", ctx)
    if requested then
      consume_ability("ranged_attack")
      self._ranged_buffer_count = (self._ranged_buffer_count or 1) - 1
      if stance then stance.released = false end
      pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_cooldown"), { action = "ranged" })
    end
  end
end

function M.do_light_melee(self)
  player_log("[PLAYER] Light melee")
  local cfg = ACTIONS.melee_light or {}
  -- Lock animation for the active+recovery window; anim.done releases early.
  -- Fallback cap keeps the lock short so missed anim.done doesn't freeze the player.
  local base_lock = math.max((cfg.active or 0.12) + (cfg.recovery or 0.14), 0.35)
  local lock_t = cfg.anim_lock or base_lock
  anim_attack(self, "punch", lock_t, { blend = 0.06 })
end

function M.do_heavy_melee(self)
  player_log("[PLAYER] Heavy melee")
  local cfg = ACTIONS.melee_heavy or {}
  local base_lock = math.max((cfg.active or 0.20) + (cfg.recovery or 0.22), 0.50)
  local lock_t = cfg.anim_lock or base_lock
  anim_attack(self, "weapon_attack", lock_t, { blend = 0.08 })
end

function M.pick_attack_bone(spine_url, attack_type)
  if not spine_url then
    return nil, nil
  end

  local candidates

  -- Weapon attacks follow the Buck near-layer item tip, then fall back toward
  -- the holding hand if a customized rig omits the tip marker.
  if attack_type == "heavy" then
    candidates = {
      "item_part_near", "item_near", "hand_near",
      "item_part_far", "item_far", "hand_far",
    }
  -- Punch_1 drives the far fist most strongly; retain the near fist and lower
  -- arms as safe custom-animation fallbacks.
  else
    candidates = {
      "hand_far", "hand_near",
      "arm_lower_far", "arm_lower_near",
    }
  end

  for _, name in ipairs(candidates) do
    local pos = BoneCollision.get_bone_position(spine_url, name)
    if pos then
      return name, pos
    end
  end
  return nil, nil
end

function M.clear_movement_contact_hitbox(self, action_name)
  local active = self._movement_contact_hitboxes
  if not active or not action_name then
    return
  end
  local id = active[action_name]
  if id then
    pcall(go.delete, id)
    active[action_name] = nil
  end
end

function M.clear_all_movement_contact_hitboxes(self)
  local active = self._movement_contact_hitboxes
  if not active then
    return
  end
  for action_name, id in pairs(active) do
    if id then
      pcall(go.delete, id)
    end
    active[action_name] = nil
  end
end

function M.spawn_movement_contact_hitbox(self, action_name, state_duration, overrides)
  local cfg = resolve_movement_contact_config(action_name)
  if not cfg then
    M.clear_movement_contact_hitbox(self, action_name)
    return nil
  end

  if overrides then
    local copy = {}
    for key, value in pairs(cfg) do copy[key] = value end
    for key, value in pairs(overrides) do copy[key] = value end
    cfg = copy
  end

  local dir = movement_action_direction(self, action_name)
  local base_lifetime = number_or_default(state_duration, cfg.default_lifetime)
  if base_lifetime <= 0 then
    base_lifetime = cfg.default_lifetime
  end
  local lifetime = cfg.lifetime or (base_lifetime + (cfg.lifetime_pad or 0))
  lifetime = math.max(0.05, lifetime or 0.05)

  local offset_y = cfg.offset_y or 0
  if cfg.anchor == "feet" then
    -- Measured from the feet, so a slam reaches the floor at any body size.
    offset_y = offset_y - (tonumber(self.collider_half_height) or 0) + (tonumber(self.foot_floor_adjust) or 0)
  elseif cfg.anchor == "head" then
    offset_y = offset_y + (tonumber(self.collider_half_height) or 0)
  end
  local offset = vmath.vector3((cfg.offset_x or 0) * dir, offset_y, 0)
  local p = go.get_position() + offset
  local url = C.URL.FACTORY.melee
  local spawn_props = {
    source_actor = msg.url(nil, go.get_id(), nil),
    dir = dir,
    lifetime = lifetime,
    damage = PlayerStats.outgoing_damage(cfg.damage),
    damage_type = PlayerElements.resolve("movement", cfg.damage_type),
    knockback = cfg.knockback,
    stun_t = cfg.stun_t,
    hit_enemy = cfg.hit_enemy,
    hit_breakable = cfg.hit_breakable,
  }
  if cfg.attack_type then
    spawn_props.attack_type = cfg.attack_type
  end

  local ok, id = pcall(factory.create, url, p, nil, spawn_props, 1)
  if not ok or not id then
    return nil
  end

  self._movement_contact_hitboxes = self._movement_contact_hitboxes or {}
  M.clear_movement_contact_hitbox(self, action_name)
  self._movement_contact_hitboxes[action_name] = id
  pcall(msg.post, id, hash("set_owner"), { owner = msg.url() })
  pcall(msg.post, id, hash("set_follow_owner"), {
    owner = go.get_id(),
    offset = offset,
  })
  return id
end

function M.spawn_melee(self, kind)
  local facing = (self.facing or 1)
  local cfg = (kind == "heavy") and ACTIONS.melee_heavy or ACTIONS.melee_light
  local spine_url = SpineVisual.resolve()
  local bone_name = M.pick_attack_bone(spine_url, kind)

  -- Hitbox offsets are configured in developer/config/game_config.lua
  -- These approximate brush/fist position during attack animations
  local hitbox_cfg = (kind == "heavy") and HITBOX_CONFIG.heavy or HITBOX_CONFIG.light
  local x_offset = (hitbox_cfg and hitbox_cfg.offset_x) or ((kind == "heavy") and 60 or 48)
  local y_offset = (hitbox_cfg and hitbox_cfg.offset_y) or ((kind == "heavy") and 20 or 10)
  local offset = vmath.vector3((facing) * x_offset, y_offset, 0)
  -- Spawn at player center + offset for a reliable initial position.
  -- If the skeleton has an attack bone, bone-following takes over each frame
  -- so the hitbox tracks the weapon throughout the swing.
  local p = go.get_position() + offset

  local url = C.URL.FACTORY.melee
  -- Lifetime = hitbox config lifetime, then anim_lock cap, then active+recovery.
  -- Hitbox must stay alive for the full swing of the attack animation.
  local lifetime = hitbox_cfg and tonumber(hitbox_cfg.lifetime)
  if not lifetime then
    lifetime = cfg and tonumber(cfg.anim_lock)
  end
  if not lifetime then
    lifetime = ((cfg and cfg.active) or ((kind == "heavy") and 0.35 or 0.18))
      + ((cfg and cfg.recovery) or ((kind == "heavy") and 0.22 or 0.14))
      + 0.06
  end
  lifetime = math.max(0.10, lifetime)
  local stun_t = (cfg and cfg.stun_t) or (hitbox_cfg and hitbox_cfg.stun_t) or ((kind=="heavy") and 0.25 or 0.12)
  local attack_type = resolve_attack_type(hitbox_cfg, cfg)
  local spawn_props = {
    dir = facing,
    lifetime = lifetime,
    damage = PlayerStats.outgoing_damage(cfg.damage or 1),
    damage_type = PlayerElements.resolve("melee", cfg.damage_type),
    knockback = cfg.knockback_px or 0,
    stun_t = stun_t,
  }
  if attack_type then
    spawn_props.attack_type = attack_type
  end
  local ok, id = pcall(factory.create, url, p, nil, {
    dir = spawn_props.dir,
    lifetime = spawn_props.lifetime,
    damage = spawn_props.damage,
    damage_type = spawn_props.damage_type,
    knockback = spawn_props.knockback,
    stun_t = spawn_props.stun_t,
    attack_type = spawn_props.attack_type,
  }, 1)
  if ok and id then
    -- Kill any previous hitbox still alive from a prior attack
    if self._attack_hitbox_id then
      pcall(go.delete, self._attack_hitbox_id)
      self._attack_hitbox_id = nil
    end
    self._attack_hitbox_id = id
    pcall(msg.post, id, hash("set_owner"), { owner = msg.url() })
    -- Attach bone-following so the hitbox tracks the weapon/fist bone each
    -- frame during the attack animation.  The initial spawn position is
    -- the fallback if the bone isn't available.
    if bone_name then
      pcall(msg.post, id, hash("set_follow_bone"), {
        bone = bone_name,
        spine_url = spine_url,
        offset = vmath.vector3(0, 0, 0),
      })
    end
  end

  -- Play attack SFX
  if kind == "heavy" then
    play_sfx("attack_heavy")
  else
    play_sfx("attack_light")
  end
end

function M.spawn_down_strike(self)
  local cfg = ACTIONS.down_strike or {}
  local hitbox_cfg = HITBOX_CONFIG.down_strike or {}
  local spine_url = SpineVisual.resolve()
  local bone_name, bone_pos = M.pick_attack_bone(spine_url, "light")
  -- Down strike offset is configured in developer/config/game_config.lua
  local y_offset = hitbox_cfg.offset_y or -32
  local p = (bone_pos or go.get_position()) + vmath.vector3(0, y_offset, 0)
  local url = C.URL.FACTORY.melee
  local attack_type = resolve_attack_type(hitbox_cfg, cfg)
  local spawn_props = {
    dir = -1,
    lifetime = cfg.hitbox_lifetime or hitbox_cfg.lifetime or 0.18,
    damage = PlayerStats.outgoing_damage(cfg.damage or 1),
    damage_type = PlayerElements.resolve("melee", cfg.damage_type),
    knockback = cfg.knockback_px or 0,
    stun_t = cfg.stun_t or hitbox_cfg.stun_t or 0.15,
    on_hit_msg = "mvtk_pogo",
  }
  if attack_type then
    spawn_props.attack_type = attack_type
  end
  local ok, id = pcall(factory.create, url, p, nil, {
    dir = spawn_props.dir,
    lifetime = spawn_props.lifetime,
    damage = spawn_props.damage,
    damage_type = spawn_props.damage_type,
    knockback = spawn_props.knockback,
    stun_t = spawn_props.stun_t,
    on_hit_msg = spawn_props.on_hit_msg,
    attack_type = spawn_props.attack_type,
  }, 1)
  if ok and id then
    pcall(msg.post, id, hash("set_owner"), { owner = msg.url() })
    if bone_name then
      pcall(msg.post, id, hash("set_follow_bone"), {
        bone = bone_name,
        spine_url = spine_url,
        offset = vmath.vector3(0, -12, 0),
      })
    end
  end
  local base_lock = math.max((cfg.hitbox_lifetime or 0.18) + 0.12, 1.6)
  local lock_t = cfg.anim_lock or base_lock
  anim_attack(self, "weapon_attack", lock_t, { allow_movement = false, blend = 0.08 })
  play_sfx("attack_down")
end

function M.spawn_melee_charged(self)
  local facing = (self.facing or 1)
  local base = ACTIONS.melee_light or {}
  local CA = ACTIONS.charge_attack or {}
  local dmg = (base.damage or 1) * (CA.damage_mult or 2.0)
  local kb = (base.knockback_px or 0) * (CA.knockback_mult or 1.5)
  local lifetime = (base.active or 0.12) + 0.06
  local spine_url = SpineVisual.resolve()
  local bone_name, bone_pos = M.pick_attack_bone(spine_url)
  local offset = vmath.vector3((facing)*16, 0, 0)
  local p = bone_pos or (go.get_position() + offset)
  local url = C.URL.FACTORY.melee
  local attack_type = resolve_attack_type(CA, base)
  local spawn_props = {
    dir = facing,
    lifetime = lifetime,
    damage = PlayerStats.outgoing_damage(dmg),
    damage_type = PlayerElements.resolve("melee", CA.damage_type or base.damage_type),
    knockback = kb,
    stun_t = CA.stun_t or 0.30,
  }
  if attack_type then
    spawn_props.attack_type = attack_type
  end
  local ok, id = pcall(factory.create, url, p, nil, {
    dir = spawn_props.dir,
    lifetime = spawn_props.lifetime,
    damage = spawn_props.damage,
    damage_type = spawn_props.damage_type,
    knockback = spawn_props.knockback,
    stun_t = spawn_props.stun_t,
    attack_type = spawn_props.attack_type,
  }, 1)
  if ok and id then
    pcall(msg.post, id, hash("set_owner"), { owner = msg.url() })
    if bone_name then
      pcall(msg.post, id, hash("set_follow_bone"), { bone = bone_name, spine_url = spine_url, offset = vmath.vector3(0,0,0) })
    end
  end
  local base_lock = (ACTIONS.melee_heavy and ACTIONS.melee_heavy.anim_lock) or 1.6
  local lock_t = CA.anim_lock or base_lock
  anim_attack(self, "weapon_attack", lock_t, { allow_movement = false, blend = 0.08 })
  play_sfx("attack_heavy")
end

function M.do_parry(self)
  if CombatConfig.feature_enabled and not CombatConfig.feature_enabled("parry", true) then
    player_log('[PLAYER] Parry disabled by combat feature settings')
    return
  end
  if ParrySystem.start_parry() then
    local cfg = CombatConfig.get().parry or {}
    if cfg.animation then
      if self._anim_is_spine then
        anim_overlay_once(self, cfg.animation, {
          blend = 0.04,
          track = 2,
          mix_blend = SPINE_MIX_BLEND_REPLACE,
        })
      else
        anim_once(self, cfg.animation, { blend = 0.04 })
      end
    end
    player_log('[PLAYER] Parry window started')
  else
    player_log('[PLAYER] Parry on cooldown')
  end
end

function M.grapple_caught(self)
  -- Another ability may spend shared stamina while the hook is in flight.
  if consume_ability("grapple") == false then
    PSTATE.cancel_grapple(self)
    return false
  end
  if _Audio and _Audio.sfx then
    _Audio.sfx("grapple_attach", { cooldown = 0 })
  end
  anim_set(self, "grapple", { force = true, loop = true })
  player_log('[PLAYER] Grapple engaged')
  return true
end

function M.do_grapple(self, input)
  local ability_id = "grapple"
  if not can_consume_ability(ability_id) then
    if input and input.grapple_down then
      player_log('[PLAYER] Grapple unavailable (locked, cooldown, or stamina).')
    end
    return false
  end

  local was_active = self._grapple_active and true or false
  PSTATE.request_grapple(self, input)

  if self._grapple_active and not was_active then
    return M.grapple_caught(self)
  end
  if self._grapple_hook then
    player_log('[PLAYER] Grapple launched')
    return true
  end

  if input and input.grapple_down then
    player_log('[PLAYER] Grapple failed (no valid anchor)')
  end
  return false
end

return M
