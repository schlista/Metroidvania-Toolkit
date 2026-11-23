--- Boss State Machine
-- Manages boss AI states and transitions
-- Handles state logic for boss behavior
--
-- @module boss_state_machine

local Util = require "mvtk.core.util"
-- Telegraphs and movement are core encounter behavior. Literal requires are
-- necessary here so Defold's dependency scanner bundles both Lua modules.
local Telegraph = require "mvtk.bosses.boss_telegraph"
local BossAnimations = Util.require_module("mvtk.bosses.boss_animations")
local MovementStrategies = require "mvtk.bosses.movement_strategies"
local SafeSound = require "mvtk.audio.safe_sound"
local Clock = require "mvtk.bosses.boss_clock"
local Runtime = require "mvtk.bosses.attack_runtime"

local function anim(boss, key)
    -- Core state-machine animations (idle/death) must play something even if
    -- the user hasn't mapped them, so use the key-fallback variant here.
    -- Code paths that care about "was this authored?" should call
    -- BossAnimations.resolve directly and branch on nil.
    if BossAnimations and BossAnimations.resolve_or_key then
        return BossAnimations.resolve_or_key(boss, key)
    end
    if BossAnimations and BossAnimations.resolve then
        return BossAnimations.resolve(boss, key) or key
    end
    return key
end

local M = {}

local function boss_label(boss)
    if type(boss) ~= "table" then
        return "boss"
    end
    local boss_data = type(boss.boss_data) == "table" and boss.boss_data or nil
    return tostring(boss.id or boss.boss_id or (boss_data and boss_data.id) or "boss")
end

-- Debug-gate all print() calls in this module so they only fire when enabled.
local _orig_print = print
local _Dbg = Util.require_config("developer.config.debug_config")
local function print(...)  -- luacheck: ignore 121
    if _Dbg.bosses and _Dbg.bosses.manager then
        _orig_print(...)
    end
end

-- Defaults are sourced from developer/config/boss_defaults.lua so users can
-- tune them without editing code. Hard-coded fallbacks only kick in if the
-- config file is missing entirely.
local Fallbacks = {
    chase_speed = 120,
    attack_range = 150,
    min_chase_distance = 80,
    telegraph_time = 0.5,
    attack_duration = 1.0,
    attack_interval_min = 2.0,
    attack_interval_max = 4.0,
    idle_deadman_seconds = 8.0,
}
local Defaults = Util.require_config("developer.config.boss_defaults", Fallbacks)

--- Boss states
M.STATES = {
    IDLE = "idle",
    MOVING = "moving",
    ATTACKING = "attacking",
    TRANSITIONING = "transitioning",
    STUNNED = "stunned",
    DEFEATED = "defeated",
}

--- Create a new state machine instance
-- @param boss Boss instance
-- @param attack_manager Supplies the live phase schedule to idle movement
-- @return State machine instance
function M.create(boss, attack_manager)
    local sm = {
        boss = boss,
        attack_manager = attack_manager,
        current_state = M.STATES.IDLE,
        previous_state = nil,
        state_time = 0,
        state_data = {},
    }

    setmetatable(sm, {__index = M})
    if boss.boss_data then boss.boss_data.state_machine = sm end

    -- Call enter function for initial state
    local enter_func = sm["enter_" .. sm.current_state]
    if enter_func then
        enter_func(sm)
    end

    return sm
end

--- Update state machine
-- @param dt Delta time
function M:update(dt)
    self.state_time = self.state_time + dt

    -- Execute current state logic
    local state_func = self["state_" .. self.current_state]
    if state_func then
        state_func(self, dt)
    end
end

-- A draw may cross several decision boundaries. The state machine and the
-- attack queue meet at those boundaries, while frame work still runs once.
function M:advance_frame(previous, dt, motion_dt)
    local boss = self.boss
    local record = boss.boss_data
    local now = previous + dt
    self._state_at = self._state_at or previous - self.state_time
    if self:is_state(M.STATES.ATTACKING) and not self.state_data.attack_started and Telegraph.refresh then
        Telegraph.refresh(boss, self.state_data.telegraph_handle)
    end
    Runtime.begin_update(boss, previous, dt)

    local first, last = Clock.steps(record, now)
    local movement = false
    if self:is_state(M.STATES.IDLE) then
        boss._hold_idle_facing = first > last
        movement = self:move_idle(boss:get_current_phase(), motion_dt, first <= last) or false
        boss._hold_idle_facing = nil
    end
    for step = first, last do
        local at = step * Clock.step
        self:advance_state(at, now)
        record._boss_clock_at = at
        if self.attack_manager and self.attack_manager.tick_stagger then
            self.attack_manager.tick_stagger(boss.boss_id, Clock.step)
        end
        if self:is_state(M.STATES.IDLE) and not Clock.reached(self._state_at, at) then
            self:state_idle(Clock.step, movement)
        end
        if boss.phase_controller then boss.phase_controller:update(Clock.step) end
    end
    self:advance_state(now)
    Runtime.finish_update(boss, motion_dt)
    Runtime.advance(boss, now)
    local lead = Clock.window_lead(dt)
    self:finish_attack(now, lead)
    if self:is_state(M.STATES.STUNNED) then self:finish_stun(now, lead) end
    Runtime.prune(boss)
    record._boss_clock_at = nil
end

function M:advance_state(at, draw_time)
    local boss = self.boss
    local record = boss.boss_data
    local reached_at = math.min(at, draw_time or at)
    local state, data = self.current_state, self.state_data
    if state == M.STATES.ATTACKING and not data.pattern then
        record._boss_clock_at = at
        self:change_state(M.STATES.IDLE)
        state, data = self.current_state, self.state_data
    end
    if state == M.STATES.ATTACKING and data.pattern and not data.attack_started then
        local due = self._state_at + (data.pattern.telegraph_time or Defaults.telegraph_time)
        if reached_at >= due then
            Runtime.advance(boss, due)
            record._boss_clock_at, boss._attack_due = due, due
            self:start_attack()
            boss._attack_due = nil
        end
    end
    record._boss_clock_at = at
    Runtime.advance(boss, reached_at)
    local phase = boss.phase_controller
    if phase and phase.advance_transition and phase:advance_transition(reached_at) then
        state, data = self.current_state, self.state_data
    end
    self.state_time = math.max(0, at - self._state_at)
    if state == M.STATES.ATTACKING then
        data.attack_timer = self.state_time
        self:finish_attack(at)
    elseif state == M.STATES.STUNNED then
        data.stun_timer = self.state_time
        self:finish_stun(at, 0)
    elseif state == M.STATES.TRANSITIONING then
        self:state_transitioning(at - (self._transition_checked_at or self._state_at))
        self._transition_checked_at = at
    end
end

function M:prepare_locomotion(phase, dt)
    MovementStrategies.prepare_frame(self.boss, phase, dt)
end

function M:update_locomotion(dt)
    MovementStrategies.update_locomotion(self.boss, dt)
end

function M:interrupt_locomotion(reset_profile)
    self.state_data.burrow_attack = nil
    MovementStrategies.interrupt(self.boss, reset_profile)
end

--- Change to a new state
-- @param new_state State to change to
-- @param state_data Optional data for the new state
function M:change_state(new_state, state_data)
    if self.current_state == new_state then
        return
    end
    if self.boss._locomotion and new_state ~= M.STATES.IDLE then
        self:interrupt_locomotion()
    end

    -- Exit current state
    local exit_func = self["exit_" .. self.current_state]
    if exit_func then
        exit_func(self)
    end

    -- Change state
    self.previous_state = self.current_state
    self.current_state = new_state
    self.state_time = 0
    self.state_data = state_data or {}
    if self._state_at then self._state_at = Clock.time(self.boss.boss_data) end
    self._transition_checked_at = nil

    print(string.format("[BOSS_SM] %s: %s -> %s", boss_label(self.boss), self.previous_state, self.current_state))

    -- Enter new state
    local enter_func = self["enter_" .. new_state]
    if enter_func then
        enter_func(self)
    end
end

--- Check if in a specific state
-- @param state State to check
-- @return true if in that state
function M:is_state(state)
    return self.current_state == state
end

--- Get current state
-- @return Current state
function M:get_state()
    return self.current_state
end

--[[============================================================================
    IDLE STATE
==============================================================================]]

function M:enter_idle()
    print(string.format("[BOSS_SM] %s entered IDLE", boss_label(self.boss)))
    self.state_data.idle_timer = 0
end

local function warn_if_idle(sm, phase, reasons, dt)
    local limit = Defaults.idle_deadman_seconds or Fallbacks.idle_deadman_seconds
    if limit <= 0 then return end
    if sm._idle_phase ~= phase then
        sm._idle_phase, sm._idle_without_attack, sm._idle_warnings = phase, 0, {}
    end
    sm._idle_without_attack = sm._idle_without_attack + dt
    if not Clock.reached(sm._idle_without_attack, limit) then return end

    if not reasons then return end
    local cause
    if reasons.status == "no_entries" then
        cause = "the phase lists no attacks"
    elseif reasons.status == "range" then
        cause = string.format("none of its attacks are in range (nearest usable range: %g pixels)",
            reasons.nearest_range)
    elseif reasons.status == "cooldown" then
        cause = "all otherwise usable attacks are on cooldown"
    elseif reasons.status == "conditions" then
        cause = "the attack conditions have never been met"
    elseif reasons.status == "height" then
        cause = "none of its floor attacks reach the player's height"
    elseif reasons.status == "floor" then
        cause = "its floor attacks could not find a floor to strike"
    end
    if not cause or sm._idle_warnings[reasons.status] then return end
    sm._idle_warnings[reasons.status] = true
    local config = sm.boss.config or {}
    local label = boss_label(sm.boss)
    _orig_print(string.format("[BOSS_SM] WARNING: %s (%s) is idle because %s",
        config.name or label, label, cause))
end

function M:move_idle(phase, dt, decision)
    if not phase or self.boss._active_charge then return end
    local schedule = self.attack_manager and self.attack_manager.get_attack_schedule
        and self.attack_manager.get_attack_schedule(self.boss, phase)
    return MovementStrategies.run(self.boss, phase, Defaults, dt, schedule and schedule.approach_distance, decision)
end

function M:state_idle(dt, movement)
    if self.boss._active_charge then return end
    self.state_data.idle_timer = self._state_at and self.state_time or self.state_data.idle_timer + dt

    -- Check if should attack
    local current_phase = self.boss:get_current_phase()
    if not current_phase then
        -- Debug: log why we can't attack
        if not self.state_data.logged_no_phase then
            print("[BOSS_SM] WARNING: No current phase - boss cannot attack!")
            print("[BOSS_SM] phase_controller exists:", self.boss.phase_controller ~= nil)
            self.state_data.logged_no_phase = true
        end
        return
    end

    -- Dispatch per-phase movement. Strategy handles position + animation;
    -- falls back to ground_chase when no profile is set.
    if movement == nil then movement = self:move_idle(current_phase, dt) end

    -- Attack interval bookkeeping.
    local interval = current_phase.attack_interval or {}
    local min_interval = interval.min or Defaults.attack_interval_min or Fallbacks.attack_interval_min
    local max_interval = interval.max or Defaults.attack_interval_max or Fallbacks.attack_interval_max
    if not self.state_data.next_attack_time then
        self.state_data.next_attack_time = math.random() * (max_interval - min_interval) + min_interval
    end

    local reasons
    local age = self.state_data.idle_timer + (self._state_at and Clock.step / 2 or 0)
    if Clock.reached(age, self.state_data.next_attack_time)
        and (not (self.boss._locomotion or self.boss._returning_to_leash)
            or not MovementStrategies.waiting_to_attack(self.boss)) then
        local pending = self.state_data.burrow_attack
        if not pending then
            local attack
            attack, reasons = self.boss:select_attack()
            if attack then pending = {attack = attack, entry = self.boss._selected_attack_entry} end
        end
        if pending then
            if not self.boss._locomotion or MovementStrategies.may_attack(self.boss) then
                self:change_state(M.STATES.ATTACKING, pending)
            else
                -- Picking consumes sequence/shuffle entries. Keep that pick
                -- through the emergence warning and start it only once.
                self.state_data.burrow_attack = pending
            end
        end
    end
    if self.current_state == M.STATES.IDLE then
        if movement == "moving" and reasons and reasons.status == "range" then reasons = nil end
        warn_if_idle(self, current_phase, reasons, dt)
    end

    -- Face player unless the active phase locks facing.
    local facing_lock = current_phase and current_phase.facing_lock == true
    if not facing_lock and self.boss.face_player then
        self.boss:face_player()
    end
end

function M:exit_idle()
    self.state_data.idle_timer = nil
    self.state_data.next_attack_time = nil
end

--[[============================================================================
    ATTACKING STATE
==============================================================================]]

function M:enter_attacking()
    local attack = self.state_data.attack
    print(string.format("[BOSS_SM] %s entered ATTACKING: %s", boss_label(self.boss), attack or "unknown"))

    self.state_data.attack_timer = 0
    self.state_data.attack_started = false
    self.state_data.attack_finished = false
    if self._state_at then Runtime.begin_turn(self.boss) end

    -- Spawn attack telegraph immediately so the wind-up is visible.
    -- Resolve the pattern once for the whole attack. A phase can change while
    -- an attack is winding up; keeping one snapshot ensures the telegraph,
    -- execution, frame updates, and cancellation all use the same authored
    -- Tiled values.
    local pattern = self.boss.get_attack_pattern and self.boss:get_attack_pattern(attack, self.state_data.entry)
    self.state_data.pattern = pattern
    if Telegraph and pattern then
        -- Lock the warning to the same horizontal facing the attack will use.
        -- This is especially important for charges, whose telegraph spans the
        -- full committed lane before movement begins.
        local phase = self.boss.get_current_phase and self.boss:get_current_phase()
        if self.boss.face_player and not (phase and phase.facing_lock == true) then
            self.boss:face_player()
        end
        if pattern.type == "charge" then
            self.boss._attack_facing_locked = self.boss.facing or 1
        end
        local tele_time = pattern.telegraph_time or Defaults.telegraph_time
        self.state_data.telegraph_handle = Telegraph.begin(self.boss, pattern, tele_time)
    end
end

function M:state_attacking(dt)
    local attack = self.state_data.attack
    if not attack then
        self:change_state(M.STATES.IDLE)
        return
    end

    self.state_data.attack_timer = self.state_data.attack_timer + dt

    -- Use the pattern snapshot captured on entry so phase changes during a
    -- telegraph cannot change the attack underneath the player.
    local pattern = self.state_data.pattern
    if not pattern then
        print(string.format("[BOSS_SM] Unknown attack pattern: %s", attack))
        self:change_state(M.STATES.IDLE)
        return
    end

    -- Telegraph phase
    local telegraph_time = pattern.telegraph_time or Defaults.telegraph_time
    if not self.state_data.attack_started and Telegraph and Telegraph.refresh then
        Telegraph.refresh(self.boss, self.state_data.telegraph_handle)
    end
    if not self.state_data.attack_started and self.state_data.attack_timer >= telegraph_time then
        self:start_attack()
    end

    self:finish_attack()
end

function M:start_attack()
    local data = self.state_data
    self._idle_phase = nil
    self.boss:execute_attack(data.attack, data.pattern)
    data.attack_started = true
end

-- The boss calls this again after advancing instances, so a charge can finish
-- on the same frame as its last travel/recovery step.
function M:finish_attack(at, lead)
    if self.current_state ~= M.STATES.ATTACKING then return end
    local pattern = self.state_data.pattern
    if not pattern then return end
    local total_time = (pattern.telegraph_time or Defaults.telegraph_time)
        + (pattern.duration or Defaults.attack_duration)
    local elapsed = at and (at - self._state_at) or self.state_data.attack_timer
    if self.state_data.attack_started and Clock.reached(elapsed + (lead or 0), total_time)
        and not Runtime.is_busy(self.boss) then
        if at then
            -- A hit or move that holds the turn past the attack's own
            -- deadline hands control back on its reference decision edge.
            local turn_end = Clock.reference_deadline(Runtime.turn_end(self.boss))
            self.boss.boss_data._boss_clock_at = math.max(self._state_at + total_time, turn_end)
        end
        self:change_state(M.STATES.IDLE)
    end
end

function M:exit_attacking()
    local charge = self.boss._active_charge
    if charge and charge.finished then
        self.boss._active_charge = nil
        charge.instance:on_cancel(nil)
    end
    self.boss._attack_facing_locked = nil
    if Telegraph and self.state_data.telegraph_handle then
        -- Telegraph self-despawns via its own duration, but cancel defensively
        -- so interrupted attacks don't leave stale visuals behind.
        local leave = Telegraph.leave_state or Telegraph.cancel
        leave(self.state_data.telegraph_handle)
        self.state_data.telegraph_handle = nil
    end
    self.state_data.attack = nil
    self.state_data.attack_timer = nil
    self.state_data.attack_started = nil
    self.state_data.attack_finished = nil
    self.state_data.pattern = nil
end

--[[============================================================================
    TRANSITIONING STATE (Phase Changes)
==============================================================================]]

function M:enter_transitioning()
    local transition = self.state_data.transition
    print(string.format("[BOSS_SM] %s entered TRANSITIONING", boss_label(self.boss)))

    self.state_data.transition_timer = 0

    -- Play transition animation
    if transition and transition.animation then
        self.boss:play_animation(transition.animation)
    end

    -- Play sound
    if self.boss.config and self.boss.config.audio and self.boss.config.audio.phase_change then
        SafeSound.play(self.boss.config.audio.phase_change)
    end
end

function M:state_transitioning(dt)
    local transition = self.state_data.transition
    if not transition then
        self:change_state(M.STATES.IDLE)
        return
    end

    self.state_data.transition_timer = self.state_data.transition_timer + dt

    local duration = transition.duration or 2.0

    if self.state_data.transition_timer >= duration then
        -- Transition complete
        self:change_state(M.STATES.IDLE)
    end
end

function M:exit_transitioning()
    self.state_data.transition = nil
    self.state_data.transition_timer = nil
end

--[[============================================================================
    STUNNED STATE
==============================================================================]]

function M:enter_stunned()
    print(string.format("[BOSS_SM] %s entered STUNNED", boss_label(self.boss)))
    self.state_data.stun_timer = 0
    if self.boss.boss_data then self.boss.boss_data.staggered = true end
    -- Knockdown interrupts pending hits. Persistent attacks stay until defeat.
    require("mvtk.bosses.attack_runtime").cancel(self.boss, "stagger")
end

function M:restart_stun(duration)
    self.state_data.stun_duration = duration
    self.state_data.stun_timer = 0
    if self._state_at then self._state_at = Clock.time(self.boss.boss_data) end
end

function M:finish_stun(at, lead)
    local due = self._state_at + (self.state_data.stun_duration or 2.0)
    if Clock.reached(at + lead, due) then
        self.boss.boss_data._boss_clock_at = due
        self:change_state(M.STATES.IDLE)
    end
end

function M:state_stunned(dt)
    self.state_data.stun_timer = self.state_data.stun_timer + dt

    local stun_duration = self.state_data.stun_duration or 2.0

    if self.state_data.stun_timer >= stun_duration then
        -- Stun ended
        self:change_state(M.STATES.IDLE)
    end
end

function M:exit_stunned()
    if self.boss.boss_data then
        self.boss.boss_data.staggered = false
        require("mvtk.bosses.boss_stagger").reset(self.boss.boss_data.stagger)
    end
    self.state_data.stun_timer = nil
    self.state_data.stun_duration = nil
end

--[[============================================================================
    DEFEATED STATE
==============================================================================]]

function M:enter_defeated()
    print(string.format("[BOSS_SM] %s entered DEFEATED", boss_label(self.boss)))

    -- Play death animation through the shared boss animation contract.
    self.boss:play_animation(anim(self.boss, "death"))

    -- Play death sound
    if self.boss.config and self.boss.config.audio and self.boss.config.audio.death then
        SafeSound.play(self.boss.config.audio.death)
    end

    -- Notify manager
    if self.boss.on_defeat then
        self.boss:on_defeat()
    end
end

--[[============================================================================
    UTILITY
==============================================================================]]

--- Force a state change (used by boss script)
-- @param state New state
-- @param data Optional state data
function M:force_state(state, data)
    self:change_state(state, data)
end

--- Get time in current state
-- @return State time in seconds
function M:get_state_time()
    return self.state_time
end

return M
