--- Phase Controller
-- Manages boss phase transitions and phase-specific behavior
-- Handles health thresholds and phase changes
--
-- @module phase_controller

local Util = require "mvtk.core.util"
local Invulnerability = require "mvtk.combat.invulnerability"
local Feedback = Util.require_module("mvtk.combat.combat_feedback")
local BossArena = Util.require_module("mvtk.bosses.boss_arena")
local BossAnimations = Util.require_module("mvtk.bosses.boss_animations")
local Audio = Util.require_module("mvtk.audio.audio")
local SafeSound = require "mvtk.audio.safe_sound"
local BossUI = require "mvtk.bosses.boss_ui"
-- A project may carry a boss_defaults.lua older than a key read here.
local Fallbacks = { iframes_on_phase_transition = 1.5 }
local Defaults = Util.require_config("developer.config.boss_defaults", Fallbacks)
local Cues = require("mvtk.bosses.transition_cues").resolve(Defaults)

local Motion = require "mvtk.bosses.boss_motion"
local M = {}
local Pause = require "mvtk.core.pause"
local Clock = require "mvtk.bosses.boss_clock"

-- Debug-gate all print() calls in this module so they only fire when enabled.
local _orig_print = print
local _Dbg = Util.require_config("developer.config.debug_config")
local function print(...)  -- luacheck: ignore 121
    if _Dbg.bosses and _Dbg.bosses.phases then
        _orig_print(...)
    end
end

local function resolve_arena_id(boss)
    if not boss then
        return nil
    end
    local config = boss.config or {}
    local data = boss.boss_data or {}
    return config.arena_id or config.arena or data.arena_id or data.arena
end

local TRANSITION_TYPE_ALIASES = {
    power_up = "rage",
    malfunction = "rage",
    final_form = "transform",
}

local function normalize_transition_type(value)
    local transition_type = tostring(value or ""):lower()
    return TRANSITION_TYPE_ALIASES[transition_type] or transition_type
end

local function positive(value)
    return value and value > 0 and value or nil
end

local function play_shake(transition, cue, opening)
    local authored = transition.camera_shake
    if not authored and (not opening or Cues.shake_enabled == false) then return end
    if Feedback and Feedback.screen_shake then
        local duration = (authored and positive(authored.duration)) or (authored and not opening and transition.duration)
            or cue.shake_duration
        local intensity = (authored and positive(authored.intensity)) or cue.shake_intensity
        if duration > 0 and intensity > 0 then pcall(Feedback.screen_shake, duration, intensity) end
    end
end

local function flash_color(cue)
    local rgba = cue.flash_color
    return vmath.vector4(rgba[1], rgba[2], rgba[3], rgba[4])
end

local function play_flash(transition, cue)
    if (Cues.flash_enabled ~= false or transition.flash == true) and cue.flash_duration > 0
        and Feedback and Feedback.flash then
        pcall(Feedback.flash, { duration = cue.flash_duration, color = flash_color(cue) })
    end
end

local function play_arena_flash(boss, transition, cue)
    if transition.flash == false then return end
    if Cues.flash_enabled == false and transition.flash ~= true then return end
    local arena_id = resolve_arena_id(boss)
    if arena_id and BossArena and BossArena.trigger_arena_effect and cue.arena_flash_duration > 0 then
        pcall(BossArena.trigger_arena_effect, arena_id, "flash", {
            color = flash_color(cue), duration = cue.arena_flash_duration,
        })
    end
end

local function resolve_transition_animation(boss, animation_name)
    if type(animation_name) ~= "string" or animation_name == "" then
        return animation_name
    end
    if BossAnimations and BossAnimations.resolve_or_key then
        return BossAnimations.resolve_or_key(boss, animation_name)
    end
    return animation_name
end

-- When every phase is authored without a health_range (or with the sentinel
-- -1, -1) evenly split [0, 1] across all phases. Explicit ranges on any
-- phase suppress the auto-split so mixed authoring still works.
function M.derive_phase_bands(phases)
    if not phases or #phases == 0 then return phases end

    local needs_derive, n = true, 0
    for _, phase in ipairs(phases) do
        if not phase.partner_defeated then
            n = n + 1
            local hr = phase.health_range
            if hr and not (hr.min == nil or hr.min == -1 or hr.max == nil or hr.max == -1) then
                needs_derive = false
            end
        end
    end
    if not needs_derive then return phases end

    -- Phase 1 covers the top band (1.0 .. (n-1)/n], phase n covers the
    -- bottom (0 .. 1/n]. get_phase_for_health walks the list top-down.
    local i = 0
    for _, phase in ipairs(phases) do
        if not phase.partner_defeated then
            i = i + 1
            local top = 1.0 - (i - 1) / n
            local bot = 1.0 - i / n
            phase.health_range = { min = bot, max = top }
        end
    end
    return phases
end

--- Create a new phase controller instance
-- @param boss Boss instance
-- @param phases Table of phase definitions
-- @return Phase controller instance
function M.create(boss, phases)
    local pc = {
        boss = boss,
        phases = M.derive_phase_bands(phases or {}),
        current_phase_index = 1,
        min_phase_index = 1,
        previous_phase_index = 0,
        transitioning = false,
        -- Preserve the already-merged preset/instance movement value so a
        -- later phase with no override can restore it after an authored phase.
        base_chase_speed = boss and boss.config and boss.config.chase_speed or nil,
    }

    setmetatable(pc, {__index = M})

    return pc
end

--- Update phase controller
-- @param dt Delta time
function M:update(dt)
    if Pause.get() then return end
    local pending = self.pending_phases
    self.pending_phases = nil
    for _, index in ipairs(pending or {}) do self:transition_to_phase(index) end
    -- Check if should change phase based on health
    self:check_phase_change()
end

function M:advance_transition(now)
    local active = self.active_transition
    if not active or Pause.get() or not Clock.reached(now, active.deadline) then return false end
    local record = self.boss.boss_data or self.boss
    local previous = record._boss_clock_at
    record._boss_clock_at = active.deadline
    self:on_phase_complete(active.phase)
    record._boss_clock_at = previous
    return true
end

--- Check if boss should change phase
function M:check_phase_change()
    if self.transitioning or self.retired then
        return  -- Already transitioning
    end
    if not (self.boss and self.boss.get_health_percent) then
        return
    end

    local record = self.boss.boss_data
    local pool = record and record.shared_pool
    local health = pool and pool.pool or record and record.health
    local max_health = pool and pool.pool_max or record and record.max_health
    if not (health and max_health and max_health > 0) then
        health, max_health = self.boss:get_health_percent() or 1, 1
    end
    local gated = record and record.config and record.config.phase_damage_gate
    local target_phase_index
    if gated then
        local edge, next_index = self:get_damage_boundary(health, max_health)
        -- An explicit gap below a band's lower edge must not make the
        -- ordinary out-of-band fallback jump all the way to the last phase.
        if health == edge then target_phase_index = next_index end
    end
    target_phase_index = target_phase_index or self:get_phase_for_health(health, max_health, gated)

    if target_phase_index ~= self.current_phase_index then
        -- Phase change needed
        self:transition_to_phase(target_phase_index)
    end
end

--- Get phase index for given health percentage.
-- Tolerant of phases authored without a health_range: a missing range is
-- treated as "this phase covers all hp" (only useful if there is a single
-- phase) so misconfigured data doesn't crash the update loop.
-- @param health Health as a fraction, or absolute health with max_health
-- @param max_health Compare absolute edges without re-dividing clamped health
-- @param gated Keep an uncovered gap in the band just below it when gating
-- @return Phase index
function M:get_phase_for_health(health, max_health, gated)
    if #self.phases == 0 then return 0 end
    max_health = max_health or 1
    local floor = math.max(self.current_phase_index or 1, self.min_phase_index or 1)
    local last, below_gap = 1, nil
    for i, phase in ipairs(self.phases) do
        if not phase.partner_defeated then
            last = i
            local hr = phase.health_range
            local min = (hr and hr.min) or 0
            local max = (hr and hr.max) or 1

            if health > min * max_health then
                if health <= max * max_health then return math.max(i, floor) end
                below_gap = below_gap or i
            end
        end
    end

    -- Default to last phase if health is 0 or below
    return math.max(gated and below_gap or last, floor)
end

-- A partner-defeated phase has no band of its own. Look only at edges that
-- would enter a later health phase, accounting for any forced/partner floor.
function M:get_damage_boundary(health, max_health)
    local floor = math.max(self.current_phase_index, self.min_phase_index)
    local previous, boundary, next_index
    for i, phase in ipairs(self.phases) do
        if not phase.partner_defeated then
            if previous and i > floor then
                local range = previous.health_range
                local edge = (range and range.min or 0) * max_health
                -- At equality the transition is still pending. Hold this edge
                -- until the controller can enter that phase, even for status ticks.
                if edge > 0 and edge <= health and (not boundary or edge > boundary) then
                    boundary, next_index = edge, i
                end
            end
            previous = phase
        end
    end
    return boundary, next_index
end

function M:blocks_direct_damage()
    return self.active_transition ~= nil and self.active_transition.protects
end

local function release_iframes(self)
    if self.release_iframes then
        self.release_iframes()
        self.release_iframes = nil
    end
end

function M:retire()
    release_iframes(self)
    self.retired = true
    self.active_transition = nil
    self.pending_phases = nil
    self.transitioning = false
end

-- A partner's defeat establishes a boss-phase floor. If a previous transition
-- is still playing, its completion runs normally; the next health check then
-- enters this boss phase with its own authored transition.
function M:hold_at_least(index)
    if not self.phases[index] then return end
    self.min_phase_index = math.max(self.min_phase_index or 1, index)
    if not self.transitioning then self:transition_to_phase(self.min_phase_index) end
end

--- Transition to a new phase
-- @param phase_index Index of phase to transition to
function M:transition_to_phase(phase_index, elapsed)
    if self.retired then return end
    if Pause.get() then
        self.pending_phases = self.pending_phases or {}
        self.pending_phases[#self.pending_phases + 1] = phase_index
        return
    end
    if phase_index < 1 or phase_index > #self.phases then
        print(string.format("[PHASE_CTRL] Invalid phase index: %d", phase_index))
        return
    end

    if phase_index <= self.current_phase_index then
        return
    end

    release_iframes(self)
    require("mvtk.bosses.attack_runtime").cancel(self.boss, "phase")
    -- A warning can still be winding up before its executor has an instance.
    -- Exit it even for an instantaneous phase change.
    local sm = self.boss.state_machine
    if sm and self.boss._locomotion then sm:interrupt_locomotion(true) end
    if sm and (sm:get_state() == "attacking" or self.transitioning and sm:get_state() == "transitioning") then
        sm:change_state("idle")
    end
    local new_phase = self.phases[phase_index]

    print(string.format("[PHASE_CTRL] %s transitioning: Phase %d -> Phase %d",
        self.boss.id, self.current_phase_index, phase_index))

    -- Store previous phase
    self.previous_phase_index = self.current_phase_index
    self.current_phase_index = phase_index

    -- Refresh the existing boss phase label through its registered HUD.
    local record = self.boss.boss_data or self.boss
    local previous = record._boss_clock_at
    if elapsed then record._boss_clock_at = math.max(0, Clock.time(record) - elapsed) end
    self.boss._phase_started_at = Clock.time(record)
    self.boss._attack_schedule = nil
    self.boss._selected_attack_entry = nil
    self.boss.last_attack_name = nil
    local pool = record.shared_pool
    if not pool or pool.lead == record.id then
        BossUI.send("update_boss_phase", {
            boss_id = pool and pool.key or self.boss.id or self.boss.boss_id,
            current_phase = phase_index,
            total_phases = #self.phases,
            phase_changed = true,
        })
    end

    -- Execute transition
    if new_phase.transition then
        self:execute_transition(new_phase.transition, phase_index)
    end

    -- Every phase change synchronizes the authored arena mechanics, even
    -- when the phase has no transition animation or delay.
    if self.boss.on_phase_change then
        self.boss:on_phase_change(self.previous_phase_index, phase_index)
    end

    if not new_phase.transition then
        -- No transition defined, instant change
        self:on_phase_complete(phase_index)
    elseif elapsed and elapsed > 0 and record.fight_time then
        self:advance_transition(record.fight_time)
    end
    record._boss_clock_at = previous
end

--- Execute phase transition
-- @param transition Transition configuration
-- @param phase_index Target phase index
function M:execute_transition(transition, phase_index)
    local duration = transition.duration or Cues.phase_duration
    local iframes = transition.iframes
    if iframes == nil and (not duration or duration <= 0) then
        iframes = Defaults.iframes_on_phase_transition or Fallbacks.iframes_on_phase_transition
    end
    local active = {
        protects = iframes == nil and duration and duration > 0,
        deadline = Clock.time(self.boss.boss_data or self.boss) + math.max(0, duration or 0),
        phase = phase_index,
    }
    self.active_transition = active
    self.transitioning = true

    print(string.format("[PHASE_CTRL] Executing %s transition", transition.type or "default"))

    -- Authored i-frames use the normal hit timer. The default instead follows
    -- this transition's lifetime, including time spent paused or slowed.
    local record = self.boss.boss_data
    if iframes and record and record.fight_time then
        iframes = iframes - math.max(0, record.fight_time - Clock.time(record))
    end
    if iframes and iframes > 0 and self.boss.boss_data then
        self.release_iframes = Invulnerability.start(self.boss.boss_data, iframes, "phase_transition", true)
    end

    -- Use registered encounter listeners, as defeat notifications do. The
    -- boss manager is a Lua module, not a gameobject message receiver.
    BossUI.send("boss_phase_enter", {
        boss_id = self.boss.id or self.boss.boss_id,
        from_phase = self.previous_phase_index,
        to_phase = phase_index,
        transition_type = transition.type,
    })

    local transition_type = normalize_transition_type(transition.type)
    local uses_extra_shake = transition_type == "cutscene" or transition_type == "transform"
        or transition_type == "rage" or transition_type == "desperation" or transition_type == "shield"
    -- Types with their own shake keep the separate opening cue. All other
    -- types apply any authored camera values to the opening cue itself.
    play_shake(uses_extra_shake and {} or transition, Cues.telegraph, true)
    play_flash(transition, Cues.telegraph)

    -- Put boss in transitioning state
    if self.boss.state_machine then
        self.boss.state_machine:change_state("transitioning", {
            -- The completion callback releases the state. Disable the state
            -- machine's standalone timeout for controller-owned transitions.
            transition = { duration = math.huge, animation = transition.animation },
            target_phase = phase_index,
        })
    end

    -- Execute transition type-specific logic
    if transition_type == "cutscene" then
        self:execute_cutscene_transition(transition)
    elseif transition_type == "teleport" then
        self:execute_teleport_transition(transition)
    elseif transition_type == "transform" then
        self:execute_transform_transition(transition)
    elseif transition_type == "rage" or transition_type == "desperation" then
        self:execute_rage_transition(transition)
    elseif transition_type == "shield" then
        self:execute_shield_transition(transition)
    end

end

--- Cutscene transition
-- @param transition Transition config
function M:execute_cutscene_transition(transition)
    print("[PHASE_CTRL] Cutscene transition")
    local cue = Cues.cutscene

    -- Play animation
    if transition.animation then
        self.boss:play_animation(resolve_transition_animation(self.boss, transition.animation))
    end

    play_shake(transition, cue)
    if transition.flash then play_flash(transition, cue) end

    if transition.new_music and Audio and Audio.music then
        pcall(Audio.music, transition.new_music, { t = cue.music_fade })
    end

    -- Could pause player input, zoom camera, etc.
end

-- Validate that a value looks like a vmath.vector3 before handing it to
-- go.set_position (which would crash on a bad type). Accepts the standard
-- userdata vector form only; tables are rejected so callers don't sneak in
-- half-built positions.
local function is_vector3(v)
    return type(v) == "userdata" and pcall(function() return v.x + v.y + v.z end)
end

--- Teleport transition
-- @param transition Transition config
function M:execute_teleport_transition(transition)
    print("[PHASE_CTRL] Teleport transition")
    -- Forced phase changes may originate in a marker's script context.
    local boss_url = self.boss.self_url or go.get_id()
    local base_scale = self.boss._base_scale or go.get_scale(boss_url)

    -- Fade out boss
    Motion.scale(boss_url, Motion.disappear_scale(base_scale), Cues.teleport.shrink_duration, "in_cubic", false, function()
        -- Move to new position
        if transition.teleport_to == "arena_center" then
            local arena_center = self.boss:get_arena_center()
            if is_vector3(arena_center) then
                go.set_position(arena_center, boss_url)
            end
        elseif is_vector3(transition.teleport_position) then
            go.set_position(transition.teleport_position, boss_url)
        end

        -- Fade in boss
        Motion.scale(boss_url, base_scale, Cues.teleport.grow_duration, "out_cubic")
    end)

    -- Play teleport sound
    if self.boss.config and self.boss.config.audio and self.boss.config.audio.teleport then
        SafeSound.play(self.boss.config.audio.teleport)
    end
end

--- Transform transition
-- @param transition Transition config
function M:execute_transform_transition(transition)
    print("[PHASE_CTRL] Transform transition")
    local cue = Cues.transform

    -- Play transform animation
    if transition.animation then
        self.boss:play_animation(resolve_transition_animation(self.boss, transition.animation))
    end

    if transition.flash then play_flash(transition, cue) end
    play_shake(transition, cue)
    play_arena_flash(self.boss, transition, cue)

    if transition.new_music and Audio and Audio.music then
        pcall(Audio.music, transition.new_music, { t = cue.music_fade })
    end
end

-- Only linked, pulse-only hazards of the requested types wake.
local function pulse_transition_hazards(boss, types)
    if not types or #types == 0 or not BossArena then return end
    if BossArena.spawn_hazard then
        for _, hazard_type in ipairs(types) do
            pcall(BossArena.spawn_hazard, hazard_type)
        end
    end
    local arena_id = resolve_arena_id(boss)
    if arena_id and BossArena.trigger_arena_effect then
        pcall(BossArena.trigger_arena_effect, arena_id, "hazard_pulse", {
            hazard_types = types,
            pulse_only = true,
        })
    end
end

--- Rage/desperation transition
-- @param transition Transition config
function M:execute_rage_transition(transition)
    print("[PHASE_CTRL] Rage/desperation transition")
    local cue = Cues.rage

    -- Play enrage animation
    if transition.animation then
        self.boss:play_animation(resolve_transition_animation(self.boss, transition.animation))
    end

    -- Arena effects
    if transition.arena_darkness then
        if BossArena and BossArena.apply_effect then
            pcall(BossArena.apply_effect, "darkness")
        end
    end

    pulse_transition_hazards(self.boss, transition.spawn_hazards)

    play_shake(transition, cue)
    if transition.flash ~= false then play_flash(transition, cue) end

    if transition.new_music and Audio and Audio.music then
        pcall(Audio.music, transition.new_music, { t = cue.music_fade })
    end
end

--- Shield transition
-- @param transition Transition config
function M:execute_shield_transition(transition)
    print("[PHASE_CTRL] Shield transition")
    local cue = Cues.shield

    -- Activate shield visual
    if transition.animation then
        self.boss:play_animation(resolve_transition_animation(self.boss, transition.animation))
    end

    pulse_transition_hazards(self.boss, transition.spawn_hazards)

    play_flash(transition, cue)
    play_shake(transition, cue)
    play_arena_flash(self.boss, transition, cue)

    if transition.new_music and Audio and Audio.music then
        pcall(Audio.music, transition.new_music, { t = cue.music_fade })
    end
end

--- Called when transition completes
-- @param phase_index Phase that was transitioned to
function M:on_phase_complete(phase_index)
    print(string.format("[PHASE_CTRL] Phase %d transition complete", phase_index))

    self.active_transition = nil
    self.transitioning = false

    -- Apply phase modifiers
    self:apply_phase_modifiers(phase_index)

    -- Arena hazards/platforms are synced by boss.script.on_phase_change,
    -- which fires earlier in transition_to_phase(). Nothing to do here —
    -- BossArena is imported only so it's discoverable to downstream edits.
    local _ = BossArena

    -- Broadcast phase-complete so listeners (arena controller, UI) can react
    -- after modifiers are applied.
    BossUI.send("boss_phase_complete", {
        boss_id = self.boss.id or self.boss.boss_id,
        phase = phase_index,
    })

    -- Explicit i-frames expire on their own timer even if they outlast this transition.

    -- Return boss to combat
    if self.boss.state_machine and self.boss.state_machine:get_state() == "transitioning" then
        self.boss.state_machine:change_state("idle")
    end
end

--- Advance to the next phase (used by weak points, timers, etc.).
function M:advance_phase()
    self:transition_to_phase(self.current_phase_index + 1)
end

--- Apply phase-specific stat modifiers
-- @param phase_index Current phase index
function M:apply_phase_modifiers(phase_index)
    local phase = self.phases[phase_index]
    if not phase then
        return
    end
    -- Every boss phase assigns this, so an omitted flag clears old immunity.
    if self.boss.boss_data then
        self.boss.boss_data.stagger_immune = phase.stagger_immune == true
    end

    require("mvtk.bosses.attack_runtime").apply_multipliers(self.boss, phase)

    -- chase_speed is an absolute movement value rather than a multiplier.
    -- The phase wins while active; an inherited (-1/missing) value restores
    -- the merged boss preset/Tiled-instance baseline captured at creation.
    if self.boss and self.boss.config then
        local phase_chase_speed = tonumber(phase.chase_speed)
        if phase_chase_speed ~= nil and phase_chase_speed >= 0 then
            self.boss.config.chase_speed = phase_chase_speed
        else
            self.boss.config.chase_speed = self.base_chase_speed
        end
    end

    -- Update attack pool
    if phase.attacks then
        self.boss.available_attacks = phase.attacks
        print(string.format("[PHASE_CTRL] Available attacks: %s", table.concat(phase.attacks, ", ")))
    end
end

--- Get current phase configuration
-- @return Current phase table
function M:get_current_phase()
    return self.phases[self.current_phase_index]
end

--- Get current phase index
-- @return Phase index (1-based)
function M:get_current_phase_index()
    return self.current_phase_index
end

--- Get total number of phases
-- @return Phase count
function M:get_phase_count()
    return #self.phases
end

--- Force a phase change (a Boss Phase Trigger, boss practice, tests).
-- The forced phase becomes a floor, like a partner's defeat (hold_at_least):
-- without it the next health check took a boss whose health is still above
-- that phase's range straight back to an earlier phase. Lower health still
-- advances to later phases.
-- @param phase_index Phase to change to
function M:force_phase(phase_index, elapsed)
    print(string.format("[PHASE_CTRL] Forcing phase change to %d", phase_index))
    if self.phases[phase_index] then
        self.min_phase_index = math.max(self.min_phase_index or 1, phase_index)
    end
    self:transition_to_phase(phase_index, elapsed)
end

--- Check if currently transitioning
-- @return true if transitioning
function M:is_transitioning()
    return self.transitioning
end

--- Get phase name/label
-- @param phase_index Optional phase index (defaults to current)
-- @return Phase name string
function M:get_phase_name(phase_index)
    phase_index = phase_index or self.current_phase_index
    local phase = self.phases[phase_index]

    if phase and phase.name then
        return phase.name
    end

    return string.format("Phase %d", phase_index)
end

return M
