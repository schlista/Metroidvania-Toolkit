-- mvtk/combat/attack_executor.lua
-- Attack timeline executor for the player.
-- Player-only: production callers are player.script and player_state.lua.

local Util = require "mvtk.core.util"
local CombatConfig = require "mvtk.combat.config"
local AttackSettings = require "mvtk.core.attack_settings"
local DamagePayload = require "mvtk.combat.damage_payload"
local CombatFeedback = require "mvtk.combat.combat_feedback"
local C = require "mvtk.core.constants"
local SpineVisual = require "mvtk.player.spine_visual"
local PlayerStats = require "mvtk.player.player_stats"
local EnergyState = require "mvtk.player.energy_state"
local Timers = require "mvtk.player.timers"

local PlayerElements = require "mvtk.combat.player_elements"

local M = {}

local BASE_HITBOX_WIDTH = 120
local BASE_HITBOX_HEIGHT = 100
-- The circle hitbox prototype's collision shape has radius 50 (see
-- developer/game/attacks/melee_hitbox_circle.collisionobject). Scale is
-- computed against this so width/height -> radius mapping stays consistent.
local BASE_HITBOX_RADIUS = 50

local function number_or(value, fallback)
    local n = tonumber(value)
    if n == nil then
        return fallback
    end
    return n
end

local function resolve_duration(window)
    return number_or(window.duration, 0)
end

local function total_duration(attack)
    local timeline = attack.timeline or {}
    return AttackSettings.recovery_start(timeline) + number_or(timeline.recovery, 0)
end

local function cooldown_key(attack)
    return attack.cooldown_group or attack.attack_id or attack.input
end

local function clear_hitboxes(self, window, keep_native_pass)
    local combat = self._combat
    if not combat then
        return
    end
    for id, owner in pairs(combat.active_hitboxes or {}) do
        if not window or owner == window then
            if keep_native_pass and type(owner) == "table" and owner.frame == combat.frame then
                owner.retiring = true
            else
                require("mvtk.combat.active_hitboxes").remove(id)
                pcall(go.delete, id)
                combat.active_hitboxes[id] = nil
                if self._attack_hitbox_id == id then self._attack_hitbox_id = nil end
            end
        end
    end
    if not window then combat.current_swing_id = nil end
end

local function begin_follow(id, follow)
    if not id or type(follow) ~= "table" then
        return
    end
    if follow.mode == "bone" and follow.bone and follow.spine_url then
        pcall(msg.post, id, hash("set_follow_bone"), {
            bone = follow.bone,
            spine_url = follow.spine_url,
            offset = follow.offset or vmath.vector3(),
        })
        return
    end
    pcall(msg.post, id, hash("set_follow_owner"), {
        owner = follow.owner,
        offset = follow.offset or vmath.vector3(),
        active = true,
    })
end

local function follow_spec(self, hitbox)
    local anchor = hitbox.anchor or {}
    local sprite_offset = anchor.sprite_offset or anchor.offset or { x = 0, y = 0 }
    local spine_offset = anchor.spine_offset or anchor.offset or { x = 0, y = 0 }
    local facing = (self.facing or 1) >= 0 and 1 or -1
    local use_spine = self._anim_is_spine and anchor.spine_bone
    if use_spine then
        return {
            mode = "bone",
            bone = anchor.spine_bone,
            spine_url = SpineVisual.resolve(),
            offset = vmath.vector3(
                facing * number_or(spine_offset.x, 0),
                number_or(spine_offset.y, 0),
                0
            ),
        }
    end
    return {
        mode = "owner",
        owner = go.get_id(),
        offset = vmath.vector3(
            facing * number_or(sprite_offset.x, 0),
            number_or(sprite_offset.y, 0),
            0
        ),
    }
end

local function attack_position(self, follow)
    local pos = go.get_position()
    local offset = (follow and follow.offset) or vmath.vector3()
    return pos + offset
end

local function projectile_dir(self, attack, projectile)
    local facing = (self.facing or 1) >= 0 and 1 or -1
    local aim = self._combat and self._combat.current and self._combat.current.aim
    if aim and aim.mode ~= "facing" and projectile.aim ~= false
        and projectile.dir_x == nil and projectile.dir_y == nil then
        return aim.x, aim.y, facing, true
    end
    local movement = attack.movement or {}
    local dx = number_or(projectile.dir_x, number_or(movement.projectile_dir_x, facing))
    local dy = number_or(projectile.dir_y, number_or(movement.projectile_dir_y, 0))
    return dx, dy, facing
end

local function to_url(value)
    if value == nil then return msg.url() end
    if type(value) == "userdata" then
        local ok, u = pcall(msg.url, value)
        if ok then return u end
    end
    return msg.url()
end

local function make_payload(self, attack, event_def, extras, kind)
    local payload = Util.merge({
        source_actor = go.get_id(),
        source_attack = attack.attack_id,
        damage_type = PlayerElements.resolve(kind, event_def.damage_type or attack.damage_type),
        reaction_type = event_def.reaction_type or attack.reaction_type,
        attack_type = event_def.action_tag or attack.attack_type,
        parryable = event_def.parryable,
        stun_t = event_def.stun_t,
    }, extras or {})
    payload.amount = PlayerStats.outgoing_damage(payload.amount)
    return DamagePayload.build(payload)
end

local function spawn_melee_hitbox(self, attack, hitbox, duration, window)
    local follow = follow_spec(self, hitbox)
    local p = attack_position(self, follow)
    local swing_id_str = self._combat and self._combat.current_swing_id or nil
    local is_circle = hitbox.shape == "circle"
    local debug_w_raw = number_or(hitbox.width, BASE_HITBOX_WIDTH)
    local debug_h_raw = number_or(hitbox.height, BASE_HITBOX_HEIGHT)
    local debug_radius_raw = number_or(hitbox.radius, debug_w_raw * 0.5)
    local scale
    if is_circle then
        local s = math.max(0.1, debug_radius_raw / BASE_HITBOX_RADIUS)
        scale = vmath.vector3(s, s, 1)
    else
        scale = vmath.vector3(
            math.max(0.1, debug_w_raw / BASE_HITBOX_WIDTH),
            math.max(0.1, debug_h_raw / BASE_HITBOX_HEIGHT),
            1
        )
    end
    local payload = make_payload(self, attack, hitbox, {
        amount = hitbox.damage,
        kx = number_or(hitbox.kx, number_or(hitbox.knockback, 0) * ((self.facing or 1) >= 0 and 1 or -1)),
        ky = number_or(hitbox.ky, 0),
    }, "melee")
    local fac_url = is_circle and C.URL.FACTORY.melee_circle or C.URL.FACTORY.melee
    local ok, id = pcall(factory.create, fac_url, p, nil, {
        lifetime = duration,
        damage = payload.amount,
        damage_type = payload.damage_type,
        knockback = number_or(hitbox.knockback, 0),
        dir = (self.facing or 1) >= 0 and 1 or -1,
        stun_t = payload.stun_t,
        on_hit_msg = hitbox.on_hit_msg or "",
        attack_type = payload.attack_type,
        source_attack = payload.source_attack or "",
        source_actor = to_url(payload.source_actor),
        parryable = payload.parryable,
        reaction_type = payload.reaction_type or "",
        kx = payload.kx,
        ky = payload.ky,
        debug_w = debug_w_raw,
        debug_h = debug_h_raw,
        debug_shape = hitbox.shape or "box",
        debug_radius = debug_radius_raw,
        swing_id = swing_id_str or "",
        cuts_projectiles = CombatConfig.feature_enabled ~= nil and CombatConfig.feature_enabled("cut_projectiles", false) and attack.cuts_projectiles ~= false,
    }, scale)
    if ok and id then
        begin_follow(id, follow)
        pcall(msg.post, id, hash("set_owner"), { owner = go.get_id() })
        self._combat.active_hitboxes[id] = window
        self._attack_hitbox_id = id
    end
end

local function spawn_projectile(self, attack, projectile)
    local offset = projectile.offset or { x = 24, y = 18 }
    local facing = (self.facing or 1) >= 0 and 1 or -1
    local anchor = go.get_position()
    local oy = number_or(offset.y, 18)
    -- origin sits on the shooter at muzzle height; the projectile sweeps
    -- origin -> spawn on its first frame so a wall the shooter is touching
    -- stops the shot instead of letting it spawn on the far side.
    local origin = vmath.vector3(anchor.x, anchor.y + oy, anchor.z)
    local dx, dy, dir, aimed = projectile_dir(self, attack, projectile)
    local reach = math.abs(number_or(offset.x, 24))
    local p = aimed and vmath.vector3(anchor.x + dx * reach, anchor.y + oy + dy * reach, anchor.z)
        or vmath.vector3(anchor.x + facing * number_or(offset.x, 24), anchor.y + oy, anchor.z)
    local knock_dir = aimed and (dx == 0 and 0 or (dx > 0 and 1 or -1)) or dir
    local payload = make_payload(self, attack, projectile, {
        amount = projectile.damage,
        kx = number_or(projectile.kx, 60 * knock_dir),
        ky = number_or(projectile.ky, aimed and 60 * dy or 0),
    }, "ranged")
    pcall(factory.create, C.URL.FACTORY.projectile, p, nil, {
        dir = dir,
        dir_x = dx,
        dir_y = dy,
        speed = number_or(projectile.speed, 1200),
        lifetime = number_or(projectile.lifetime, 1.5),
        damage = payload.amount,
        damage_type = payload.damage_type,
        attack_type = payload.attack_type,
        source_attack = payload.source_attack or "",
        source_actor = projectile.reflected and C.URL.PLAYER or to_url(payload.source_actor),
        parryable = payload.parryable,
        reaction_type = payload.reaction_type or "",
        kx = payload.kx,
        ky = payload.ky,
        stun_t = payload.stun_t,
        origin_x = origin.x,
        origin_y = origin.y,
        probe_origin = true,
        projectile_visual = projectile.visual or "",
    }, 1)
end

-- Called from a perfect parry or an enemy shot's melee-overlap check. Both
-- paths use the ordinary player shot factory and outgoing damage scaling.
function M.reflect_projectile(self, reflection)
    local Counterplay = require "mvtk.combat.projectile_counterplay"
    local cfg = CombatConfig.get().projectiles or {}
    local pos = go.get_position()
    local dx, dy = Counterplay.direction(reflection.source_actor, pos,
        reflection.fallback_x or -(self.facing or 1), reflection.fallback_y)
    spawn_projectile(self, {attack_id="reflected_shot", damage_type=reflection.damage_type}, {
        offset={x=0,y=0}, dir_x=dx, dir_y=dy, aim=false, reflected=true,
        speed=(reflection.speed or 300) * (cfg.reflect_speed_mult or 1.2),
        lifetime=cfg.reflect_lifetime or 1.5,
        damage=(reflection.damage or 1) * Counterplay.damage_mult(reflection.damage_mult),
        visual=reflection.visual, parryable=false,
    })
end

local function spawn_window(self, attack, window, state)
    local duration = math.max(0.04, resolve_duration(window))
    -- Allocate a per-active-window swing_id used by all hitboxes in this
    -- window. mvtk.combat.swing_registry uses it to dedup hits across
    -- overlapping sibling hitboxes (e.g. tip-damage + body-damage). Each new
    -- active window gets a fresh id, so a multi-hit attack still hits the
    -- same enemy once per window.
    if self._combat then
        self._combat.swing_counter = (self._combat.swing_counter or 0) + 1
        self._combat.current_swing_id = string.format(
            "%s:%s:%d",
            Util.hash_to_stable_string(go.get_id()),
            tostring(attack.attack_id or "?"),
            self._combat.swing_counter
        )
    end
    for _, hitbox in ipairs(window.hitboxes or {}) do
        spawn_melee_hitbox(self, attack, hitbox, duration, state)
    end
    if window.projectile then
        spawn_projectile(self, attack, window.projectile)
    end
end

local function apply_start_movement(self, attack)
    local movement = attack.movement or {}
    if movement.impulse_x or movement.impulse_y then
        self.vx = (self.vx or 0) + number_or(movement.impulse_x, 0) * ((self.facing or 1) >= 0 and 1 or -1)
        local impulse_y = number_or(movement.impulse_y, 0)
        self.vy = (self.vy or 0) + impulse_y
        if impulse_y ~= 0 then self._jump_cut_pending = nil end
    end
end

local function update_attack_motion(self, attack)
    local movement = attack.movement or {}
    if movement.hold_vy_min ~= nil and (self.vy or 0) < movement.hold_vy_min then
        self.vy = movement.hold_vy_min
        self._jump_cut_pending = nil
    end
    if movement.hold_vy_max ~= nil and (self.vy or 0) > movement.hold_vy_max then
        self.vy = movement.hold_vy_max
        self._jump_cut_pending = nil
    end
end

function M.sample_attack_motion(self, offset)
    local sample = self._attack_vertical_sample
    if sample and sample.opening + offset < sample.finish - 1e-10 then
        update_attack_motion(self, sample.attack)
    end
end

local function current_attack(self)
    return self._combat and self._combat.current or nil
end

local function attack_deadline(current, seconds)
    return current.phase_start + Timers.reference_duration(seconds - current.phase_start, current.scale)
end

local function within_window(current, start, finish, opening_dt, opening_offset)
    if current.reference_trace or not current.grid_time then
        local t = opening_offset and current.t + opening_offset or current.t
        return t >= start and t <= finish
    end
    local earliest = attack_deadline(current, start)
    local steps = math.max(0, math.floor((finish - current.phase_start) / Timers.combat_engine_step(current.scale)) + 1)
    local latest = current.phase_start + steps * Timers.REFERENCE_STEP * current.scale
    local sample
    if opening_offset then
        -- A motion owner already has the reference opening, possibly inside
        -- this display draw. Allow for binary32 display-delta accumulation.
        sample = current.grid_time + opening_offset + 1e-7
    else
        local frame = opening_dt or current.frame_dt or 0
        local phase = opening_dt and (Timers.REFERENCE_STEP * current.scale - frame) or 0
        sample = current.grid_time + frame / 2 - phase + 1e-10
    end
    return sample >= earliest and sample < latest
end

local function reached(current, seconds, opening)
    if current.reference_trace then return current.t >= seconds end
    local deadline = attack_deadline(current, seconds)
    if opening then deadline = math.max(Timers.REFERENCE_STEP * current.scale, deadline) end
    return current.grid_time + 1e-10 >= deadline
end

local function dispatch_windows(self, current, frame)
    for index, window in ipairs(current.attack.timeline.active_windows or {}) do
        local start_t = number_or(window.start, 0)
        local finish_t = start_t + resolve_duration(window)
        local state = current.spawned_windows[index]
        if not state and reached(current, start_t, true) then
            state = { frame = frame }
            current.spawned_windows[index] = state
            spawn_window(self, current.attack, window, state)
        end
        if type(state) == "table" and reached(current, finish_t) then
            current.spawned_windows[index] = "done"
            clear_hitboxes(self, state, true)
        end
    end
end

function M.init(self, hooks)
    self._combat = {
        hooks = hooks or {},
        current = nil,
        queued_attack_id = nil,
        cooldowns = {},
        active_hitboxes = {},
        frame = 0,
        counter_window_t = 0,
        counter_target = nil,
    }
end

function M.is_active(self)
    return current_attack(self) ~= nil
end

function M.can_cancel_to(self, action_name, opening_dt, opening_offset)
    local current = current_attack(self)
    if not current then
        return true
    end
    if action_name == "parry" and not CombatConfig.feature_enabled("parry", true) then
        return false
    end
    if not CombatConfig.feature_enabled("attack_cancels", true) then
        return false
    end
    for _, window in ipairs(current.attack.cancel_windows or {}) do
        local start_t = number_or(window.start, 0)
        local finish_t = number_or(window.finish, current.total_duration)
        if within_window(current, start_t, finish_t, opening_dt, opening_offset) then
            local actions = window.actions or {}
            if actions[action_name] then
                return true
            end
        end
    end
    return false
end

function M.can_queue_combo(self, intent)
    local current = current_attack(self)
    if not current then
        return false
    end
    if not CombatConfig.feature_enabled("combo_chaining", true) then
        return false
    end
    local combo_links = current.attack.combo_links or {}
    local next_id = combo_links[intent]
    if not next_id then
        return false
    end
    if intent == "heavy" and not CombatConfig.feature_enabled("mixed_finishers", true) then
        return false
    end
    local combo_window = current.attack.combo_window or {}
    local start_t = AttackSettings.combo_start(combo_window, current.total_duration,
        current.attack.timeline and current.attack.timeline.recovery)
    local finish_t = start_t + number_or(combo_window.duration, 0.35)
    return within_window(current, start_t, finish_t)
end

local function start_attack(self, attack, ctx, elapsed)
    local cost = tonumber(attack.energy_cost) or 0
    if cost > 0 and EnergyState.enabled() then
        EnergyState.consume(cost, { reason = "attack" })
    end
    clear_hitboxes(self, nil, true)
    if attack.state == "counter" then
        Timers.clear_window(self._combat, "counter_window_t")
    end
    local total = total_duration(attack)
    self._combat.current = {
        attack = attack,
        t = 0,
        grid_time = elapsed or 0,
        phase_start = 0,
        scale = 1,
        reference_trace = not elapsed or elapsed == 0,
        total_duration = total,
        spawned_windows = {},
        aim = ctx and ctx.aim, -- Animation hook reads this immediately below.
    }
    self._combat.queued_attack_id = nil
    self._attack = {
        elapsed = 0,
        ground = ctx and ctx.grounded or false,
        attack_id = attack.attack_id,
    }
    apply_start_movement(self, attack)
    if self._combat.hooks and self._combat.hooks.play_attack_animation then
        self._combat.hooks.play_attack_animation(self, attack)
    end
    if attack.sfx and attack.sfx.start then
        CombatFeedback.play_sfx(attack.sfx.start)
    end
end

local function resolve_attack(self, attack_id, ctx)
    return CombatConfig.resolve_attack(attack_id)
end

local function attack_ready(self, attack)
    local key = cooldown_key(attack)
    local cooldown = self._combat.cooldowns[key] or 0
    if cooldown > 0 then return false end
    local cost = tonumber(attack.energy_cost) or 0
    if cost > 0 and EnergyState.enabled() and not EnergyState.has(cost) then
        return false, "energy"
    end
    return true
end

-- Runtime-only policy, checked before any attack side effect (including combos).
local request_filter
function M.set_request_filter(callback) request_filter = callback end

-- The second result identifies an ability variant that started on this call.
-- A queued combo only accepts the press; it does not start that variant.
function M.request(self, intent, ctx)
    local combat = self._combat
    if not combat then
        return false
    end

    if combat.counter_window_t > 0 then
        ctx = Util.merge(ctx or {}, { counter_window = true })
    end

    local current = current_attack(self)
    if current and M.can_queue_combo(self, intent) then
        local queued_id = current.attack.combo_links[intent]
        local queued = resolve_attack(self, queued_id, ctx)
        if request_filter and (not queued or not request_filter(queued.action_tag)) then return false end
        combat.queued_attack_id = queued_id
        return true
    end
    if current then
        return false
    end

    local attack_id, started_ability = CombatConfig.resolve_attack_for_input(intent, ctx or {})
    if not attack_id then
        return false
    end
    local attack = resolve_attack(self, attack_id, ctx)
    if not attack then return false end
    if request_filter and not request_filter(attack.action_tag) then return false end
    local ready, reason = attack_ready(self, attack)
    if not ready then
        if reason == "energy" and attack.sfx and attack.sfx.refuse then
            CombatFeedback.play_sfx(attack.sfx.refuse)
        end
        return false
    end
    start_attack(self, attack, ctx or {})
    return true, started_ability
end

function M.update(self, dt, ctx)
    local combat = self._combat
    if not combat then
        return
    end

    self._attack_vertical_sample = nil
    if dt > 0 then
        combat.frame = combat.frame + 1
        for _, window in pairs(combat.active_hitboxes) do
            if type(window) == "table" and window.retiring then clear_hitboxes(self, window) end
        end
    end
    for key, value in pairs(combat.cooldowns) do
        if type(value) == "number" then Timers.tick_combat_window(combat.cooldowns, key, dt) end
    end
    if Timers.tick_combat_window(combat, "counter_window_t", dt) then
        combat.counter_target = nil
    end

    local current = combat.current
    if not current then
        return
    end

    local opening = current.grid_time
    local scale = Timers.combat_scale(dt)
    if dt > 0 and current.scale ~= scale then current.phase_start, current.scale = opening, scale end
    current.t = current.t + dt
    current.frame_dt = Timers.combat_delta(dt, scale)
    current.grid_time = current.grid_time + current.frame_dt
    if dt > 0 and not Timers.combat_reference_frame(dt, scale) then current.reference_trace = false end
    if self._attack then
        self._attack.elapsed = current.t
    end

    local movement = current.attack.movement
    if current.reference_trace or not self._cfg then
        update_attack_motion(self, current.attack)
    elseif movement and (movement.hold_vy_min or movement.hold_vy_max) then
        local sample = current.vertical_sample
        if not sample then
            sample = { attack = current.attack }
            current.vertical_sample = sample
        end
        sample.opening = opening
        sample.finish = attack_deadline(current, current.total_duration)
        self._attack_vertical_sample = sample
        if opening == 0 then self._vertical_grid = nil end
    end

    dispatch_windows(self, current, combat.frame)

    if not reached(current, current.total_duration) then
        return
    end

    clear_hitboxes(self, nil, true)
    local elapsed = current.reference_trace and 0
        or math.max(0, current.grid_time - attack_deadline(current, current.total_duration))
    Timers.start_combat_window(combat.cooldowns, cooldown_key(current.attack), number_or(current.attack.cooldown, 0), elapsed)
    local queued_attack_id = combat.queued_attack_id
    combat.current = nil
    self._attack = nil

    if queued_attack_id then
        local next_attack = resolve_attack(self, queued_attack_id, ctx or {})
        combat.queued_attack_id = nil
        if next_attack and (not request_filter or request_filter(next_attack.action_tag)) and attack_ready(self, next_attack) then
            start_attack(self, next_attack, ctx or {}, elapsed)
            if elapsed > 0 then
                combat.current.scale = current.scale
                dispatch_windows(self, combat.current, combat.frame)
            end
        end
    end
end

function M.on_animation_done(self)
    local current = current_attack(self)
    if not current then
        self._attack = nil
        clear_hitboxes(self, nil, true)
        return
    end
    if reached(current, current.total_duration) then
        clear_hitboxes(self, nil, true)
        self._combat.current = nil
        self._attack = nil
    end
end

function M.cancel(self)
    if not self._combat then
        return
    end
    clear_hitboxes(self)
    self._combat.current = nil
    self._combat.queued_attack_id = nil
    self._attack = nil
end

function M.open_counter_window(self, duration, attacker_url)
    if not self._combat then
        return
    end
    if not CombatConfig.feature_enabled("parry_counter", true) then
        return
    end
    duration = number_or(duration, 0)
    if duration > self._combat.counter_window_t then
        Timers.start_combat_window(self._combat, "counter_window_t", duration)
    end
    self._combat.counter_target = attacker_url or self._combat.counter_target
end

return M
