-- mvtk/bosses/boss_arena.lua
-- ============================================================================
-- Boss Arena System - Phase-Specific Arena Mechanics
-- ============================================================================
-- Manages arena mechanics that change during boss phases:
-- hazards, platforms, environmental effects, and boundaries.
--
-- Usage:
--   local BossArena = require "mvtk.bosses.boss_arena"
--
--   BossArena.setup_arena("forest_boss", {
--       bounds = {x = 0, y = 0, width = 800, height = 400},
--       phases = {
--           [2] = { effects = {"darkness"}, transition_effect = "shake" },
--       }
--   })
--
-- Arena hazards and platforms are Tiled objects baked into the room
-- collection (hazards with active_phases, boss add spawners, moving
-- platforms). This module records phase hazard ids for bookkeeping only and
-- creates no game objects; the old runtime spawners named factories that no
-- game object has.

local Util = require "mvtk.core.util"
local Debug = Util.require_config("developer.config.debug_config")
-- Call-time lookup: combat_feedback stays out of this module's load order.
local function feedback()
    return Util.require_module("mvtk.combat.combat_feedback")
end

local M = {}
local Pause = require "mvtk.core.pause"
local Pulse = require "mvtk.bosses.arena_hazard_pulse"
local Clock = require "mvtk.bosses.boss_clock"

-- ============================================================================
-- DATA STRUCTURES
-- ============================================================================

local arenas = {}           -- arena_id -> arena_data
local active_arena = nil
local clear_attack_effects
local timed_pulses = {}

-- Hazard types
M.HAZARD_TYPES = {
    FLOOR_SPIKES = "floor_spikes",
    CEILING_SPIKES = "ceiling_spikes",
    WALL_SPIKES = "wall_spikes",
    LAVA_FLOOR = "lava_floor",
    ACID_POOLS = "acid_pools",
    FALLING_DEBRIS = "falling_debris",
    LASER_BEAMS = "laser_beams",
    POISON_GAS = "poison_gas",
    ELECTRIC_FLOOR = "electric_floor",
    WIND_ZONES = "wind_zones",
    DARKNESS = "darkness",
}

-- Debug logging
local log = Util.make_debug_log("[BOSS_ARENA]", function()
    return Debug.global and Debug.global.enable
end)

local function optional_id(value)
    local id = Util.normalize_hash_string(value)
    if id and string.lower(id) == "none" then
        return nil
    end
    return id
end

-- ============================================================================
-- ARENA SETUP
-- ============================================================================

--- Setup a boss arena
-- @param arena_id Unique identifier
-- @param config Arena configuration
function M.setup_arena(arena_id, config)
    config = config or {}

    arenas[arena_id] = {
        id = arena_id,
        boss_id = config.boss_id,
        -- Room whose doors lock during the fight (arena ids are not rooms).
        room_id = config.room_id,

        -- Boundaries. bounds_authored = false means the placeholder below, which
        -- must never be used to confine a boss (see boss_confinement.lua).
        bounds = config.bounds or {x = 0, y = 0, width = 800, height = 400},
        bounds_authored = config.bounds ~= nil,
        -- Phase configurations
        phases = config.phases or {},
        current_phase = 0,

        -- Active elements
        active_hazards = {},
        active_platforms = {},
        active_effects = {},

        -- Hazard definitions
        hazard_configs = config.hazard_configs or {},
        platform_configs = config.platform_configs or {},

        -- Callbacks
        on_phase_change = config.on_phase_change,
        on_hazard_hit = config.on_hazard_hit,

        -- State
        locked = false,
        clock = 0,
        in_transition = false,
    }

    log("Setup arena:", arena_id)
end

--- Activate an arena
-- @param arena_id Arena to activate
function M.activate_arena(arena_id)
    local arena = arenas[arena_id]
    if not arena then
        log("ERROR: Arena not found:", arena_id)
        return false
    end

    if active_arena and active_arena ~= arena then
        clear_attack_effects()
        Pulse.clear(active_arena.id)
        active_arena.phase_deadlines, active_arena.paused_phases = nil, nil
        active_arena.in_transition = false
    end
    active_arena = arena
    arena.locked = true
    arena.current_phase = 0
    arena.clock = 0
    arena.phase_deadlines, arena.paused_phases = nil, nil
    arena.in_transition = false

    -- Lock arena doors
    M.lock_doors(arena)

    log("Activated arena:", arena_id)
    return true
end

-- Effects that outlive the arena's world: the player's arena gravity and slow motion.
local function release_global_effects()
    require("mvtk.player.player_stats").clear_source("arena:gravity")
    if M._slow_motion_active then
        Pause.set_speed_factor("arena_slow_motion", nil)
        M._slow_motion_active = nil
    end
end

--- Deactivate current arena
function M.deactivate_arena()
    release_global_effects()
    if not active_arena then return end
    Pulse.clear(active_arena.id)
    require("mvtk.enemies.enemy_spawn_service").despawn_owner("arena:" .. active_arena.id, "arena_deactivated")

    -- Clear all hazards and platforms
    M.clear_all_hazards()
    M.clear_all_platforms()
    M.clear_all_effects()

    -- Unlock doors
    M.unlock_doors(active_arena)

    active_arena.locked = false
    active_arena.current_phase = 0
    active_arena.phase_deadlines, active_arena.paused_phases = nil, nil
    active_arena.in_transition = false

    log("Deactivated arena:", active_arena.id)
    active_arena = nil
end

-- ============================================================================
-- PHASE MANAGEMENT
-- ============================================================================

local function apply_due_phases(arena)
    local deadlines = arena.phase_deadlines
    if not deadlines then return end
    while active_arena == arena and deadlines[1] and Clock.reached(arena.clock, deadlines[1].time) do
        local due = table.remove(deadlines, 1)
        if not due.escalate or due.phase > arena.current_phase then M.apply_phase(due.phase) end
    end
    if #deadlines == 0 then
        arena.phase_deadlines = nil
        arena.in_transition = false
    end
end

--- Transition to a new phase
-- @param phase_number Phase number to transition to
-- @param transition_time Optional transition duration
-- @param escalate_only Optional monotonic application for a grouped encounter
function M.transition_to_phase(phase_number, transition_time, escalate_only, elapsed)
    local arena = active_arena
    if not arena then return end
    if Pause.get() then
        arena.paused_phases = arena.paused_phases or {}
        table.insert(arena.paused_phases, {phase = phase_number, time = transition_time, escalate = escalate_only})
        return
    end

    local phase_config = arena.phases[phase_number]
    if not phase_config then
        log("WARNING: Phase", phase_number, "not configured")
        return
    end

    transition_time = transition_time or phase_config.transition_time or 1.0

    log("Transitioning to phase", phase_number)

    arena.in_transition = true
    local due = arena.clock + math.max(0, transition_time) - (elapsed or 0)
    local deadlines = arena.phase_deadlines or {}
    arena.phase_deadlines = deadlines
    local index = #deadlines + 1
    while index > 1 and deadlines[index - 1].time > due do index = index - 1 end
    table.insert(deadlines, index, {phase = phase_number, time = due, escalate = escalate_only})

    -- Callback for phase change
    if arena.on_phase_change then
        arena.on_phase_change(arena.current_phase, phase_number)
    end

    -- Start transition effects
    if phase_config.transition_effect then
        M.play_transition_effect(phase_config.transition_effect)
    end
    if elapsed and elapsed > 0 then apply_due_phases(arena) end
end

--- Apply a phase configuration
-- @param phase_number Phase number to apply
function M.apply_phase(phase_number)
    if not active_arena then return end

    local phase_config = active_arena.phases[phase_number]
    if not phase_config then return end

    active_arena.current_phase = phase_number
    active_arena.in_transition = active_arena.phase_deadlines ~= nil and #active_arena.phase_deadlines > 0

    log("Applying phase", phase_number)

    -- Clear previous hazards/platforms
    M.clear_all_hazards()
    M.clear_all_platforms()

    -- Spawn new hazards
    if phase_config.hazards then
        for _, hazard_id in ipairs(phase_config.hazards) do
            M.spawn_hazard(hazard_id)
        end
    end

    -- Spawn new platforms
    if phase_config.platforms then
        for _, platform_id in ipairs(phase_config.platforms) do
            M.spawn_platform(platform_id)
        end
    end

    -- Apply effects
    if phase_config.effects then
        for _, effect_id in ipairs(phase_config.effects) do
            M.apply_effect(effect_id)
        end
    end

    -- Apply arena modifications
    if phase_config.bounds then
        M.set_arena_bounds(phase_config.bounds)
    end

    if phase_config.gravity then
        M.set_gravity(phase_config.gravity)
    end

    if phase_config.darkness then
        M.set_darkness(phase_config.darkness)
    end

    -- Notify
    pcall(msg.post, "main:/main_go#script", hash("arena_phase_changed"), {
        arena_id = active_arena.id,
        phase = phase_number
    })
end

-- ============================================================================
-- HAZARD MANAGEMENT
-- ============================================================================

--- Spawn a hazard
-- @param hazard_id Hazard identifier
-- @param override_config Optional config override
function M.spawn_hazard(hazard_id, override_config)
    if not active_arena then return end

    local config = active_arena.hazard_configs[hazard_id] or {}
    if override_config then
        for k, v in pairs(override_config) do
            config[k] = v
        end
    end

    local hazard = {
        id = hazard_id,
        type = config.type or hazard_id,
        active = true,
        timer = 0,
        config = config,
        game_objects = {},
    }

    active_arena.active_hazards[hazard_id] = hazard

    log("Spawned hazard:", hazard_id)
end

--- Remove a hazard
-- @param hazard_id Hazard identifier
function M.remove_hazard(hazard_id)
    if not active_arena then return end

    local hazard = active_arena.active_hazards[hazard_id]
    if not hazard then return end

    -- Delete game objects
    for _, go_id in ipairs(hazard.game_objects) do
        pcall(function() go.delete(go_id) end)
    end

    active_arena.active_hazards[hazard_id] = nil

    log("Removed hazard:", hazard_id)
end

--- Clear all hazards
function M.clear_all_hazards()
    if not active_arena then return end

    for hazard_id, _ in pairs(active_arena.active_hazards) do
        M.remove_hazard(hazard_id)
    end
end

-- ============================================================================
-- PLATFORM MANAGEMENT
-- ============================================================================

--- Spawn a platform
-- @param platform_id Platform identifier
function M.spawn_platform(platform_id)
    if not active_arena then return end

    local config = active_arena.platform_configs[platform_id] or {}

    local platform = {
        id = platform_id,
        type = config.type or "static",
        active = true,
        config = config,
        game_object = nil,
    }

    active_arena.active_platforms[platform_id] = platform

    log("Spawned platform:", platform_id)
end

--- Remove a platform
-- @param platform_id Platform identifier
function M.remove_platform(platform_id)
    if not active_arena then return end

    local platform = active_arena.active_platforms[platform_id]
    if not platform then return end

    if platform.game_object then
        pcall(function() go.delete(platform.game_object) end)
    end

    active_arena.active_platforms[platform_id] = nil

    log("Removed platform:", platform_id)
end

--- Clear all platforms
function M.clear_all_platforms()
    if not active_arena then return end

    for platform_id, _ in pairs(active_arena.active_platforms) do
        M.remove_platform(platform_id)
    end
end

-- ============================================================================
-- EFFECTS MANAGEMENT
-- ============================================================================

local EFFECT_OUTPUTS = {
    darkness = function(level)
        pcall(msg.post, "main:/light_manager#script", hash("set_darkness"), {level = level})
    end,
    gravity = function(scale)
        local Stats = require "mvtk.player.player_stats"
        if not scale or scale == 1 then Stats.clear_source("arena:gravity")
        else Stats.set_source("arena:gravity", {gravity_mult=scale}, {layer="temporary"}) end
    end,
    slow_motion = function(factor)
        Pause.set_speed_factor("arena_slow_motion", factor)
        M._slow_motion_active = factor and true
    end,
}

-- The phase supplies the baseline. Timed attacks temporarily override it,
-- including when two bosses apply an effect to the same arena.
local function set_effect_output(channel, value, owner)
    local output = EFFECT_OUTPUTS[channel]
    if not active_arena then output(value); return end
    local outputs = active_arena.effect_outputs
    if not outputs then
        outputs = {}
        active_arena.effect_outputs = outputs
    end
    local state = outputs[channel]
    if not state then
        state = {overrides = {}}
        outputs[channel] = state
    end
    local overrides = state.overrides
    if owner then
        for i = #overrides, 1, -1 do
            if overrides[i].owner == owner then table.remove(overrides, i) end
        end
        if value ~= nil then overrides[#overrides + 1] = {owner = owner, value = value} end
    else
        state.baseline = value
    end
    local top = overrides[#overrides]
    local effective = top and top.value or state.baseline
    if effective ~= state.effective or (not owner and not top) then
        state.effective = effective
        output(effective)
    end
end

clear_attack_effects = function()
    for channel, state in pairs(active_arena.effect_outputs or {}) do
        if #state.overrides > 0 then
            state.overrides = {}
            state.effective = state.baseline
            EFFECT_OUTPUTS[channel](state.baseline)
        end
    end
end

--- Apply an arena effect
-- @param effect_id Effect identifier
-- @param owner Optional attack instance that can later release this effect
function M.apply_effect(effect_id, owner)
    if not active_arena then return end

    local effect_fn = M.effect_handlers[effect_id]
    if effect_fn then
        effect_fn(active_arena, owner)
        if not owner then active_arena.active_effects[effect_id] = true end
        log("Applied effect:", effect_id)
        return true
    end
end

--- Remove an arena effect
-- @param effect_id Effect identifier
function M.remove_effect(effect_id, owner)
    if not active_arena then return end

    local remove_fn = M.effect_removers[effect_id]
    if remove_fn then
        remove_fn(active_arena, owner)
    end

    if not owner then active_arena.active_effects[effect_id] = nil end
    log("Removed effect:", effect_id)
end

--- Clear all effects
function M.clear_all_effects()
    if not active_arena then return end

    for effect_id, _ in pairs(active_arena.active_effects) do
        M.remove_effect(effect_id)
    end
    for channel, state in pairs(active_arena.effect_outputs or {}) do
        if state.effective ~= nil then EFFECT_OUTPUTS[channel](nil) end
    end
    active_arena.effect_outputs = nil
end

-- Effect handlers
M.effect_handlers = {
    screen_shake = function(arena)
        local Feedback = feedback()
        if Feedback then pcall(Feedback.screen_shake, nil, "light") end
    end,

    darkness = function(arena, owner)
        set_effect_output("darkness", 0.7, owner)
    end,

    slow_motion = function(arena, owner)
        set_effect_output("slow_motion", 0.5, owner)
    end,

    low_gravity = function(arena, owner)
        set_effect_output("gravity", 0.5, owner)
    end,

    high_gravity = function(arena, owner)
        set_effect_output("gravity", 1.5, owner)
    end,

    rain = function(arena)
        pcall(msg.post, "/fx#weather", "start_rain", {intensity = 1.0})
    end,

    fire_bg = function(arena)
        pcall(msg.post, "/fx#background", "set_theme", {theme = "fire"})
    end,
}

M.effect_removers = {
    screen_shake = function(arena)
        -- Gamefeel shakes decay on their own; there is nothing to stop.
    end,

    darkness = function(arena, owner)
        set_effect_output("darkness", nil, owner)
    end,

    slow_motion = function(arena, owner)
        set_effect_output("slow_motion", nil, owner)
    end,

    low_gravity = function(arena, owner)
        set_effect_output("gravity", nil, owner)
    end,

    high_gravity = function(arena, owner)
        set_effect_output("gravity", nil, owner)
    end,

    rain = function(arena)
        pcall(msg.post, "/fx#weather", "stop_rain")
    end,

    fire_bg = function(arena)
        pcall(msg.post, "/fx#background", "set_theme", {theme = "default"})
    end,
}

-- ============================================================================
-- ARENA MODIFICATIONS
-- ============================================================================

--- Lock arena doors
-- Locking uses the arena's ROOM id. Posting the arena id (e.g.
-- "pt4_arena_26") only logged "no door data"; BossManager.lock_arena already
-- locks by room, and a second lock of the same room is ignored.
function M.lock_doors(arena)
    if not (arena and arena.room_id) then return end
    pcall(msg.post, "main:/room_manager#script", hash("lock_room"), {
        room_id = arena.room_id,
        source = "boss_arena"
    })
end

--- Unlock arena doors
function M.unlock_doors(arena)
    if not (arena and arena.room_id) then return end
    pcall(msg.post, "main:/room_manager#script", hash("unlock_room"), {
        room_id = arena.room_id,
        source = "boss_arena"
    })
end

--- Set arena boundaries
function M.set_arena_bounds(bounds)
    if not active_arena then return end
    active_arena.bounds = bounds
    active_arena.bounds_authored = bounds ~= nil
    -- Update any boundary-dependent systems
end

--- Set gravity
function M.set_gravity(scale)
    set_effect_output("gravity", scale)
end

--- Set darkness level
function M.set_darkness(level)
    set_effect_output("darkness", level)
end

--- Play transition effect
function M.play_transition_effect(effect_type)
    local Feedback = feedback()
    if effect_type == "flash" then
        if Feedback then pcall(Feedback.flash, {color = vmath.vector4(1, 1, 1, 1), duration = 0.3}) end
    elseif effect_type == "shake" then
        if Feedback then pcall(Feedback.screen_shake, 0.5, 1.0) end
    elseif effect_type == "fade" then
        pcall(msg.post, "/fx#screen", "fade", {duration = 0.5})
    end
end

-- ============================================================================
-- UPDATE
-- ============================================================================

-- Called once by GameManager during gameplay. A transition can start a
-- pulse on an arena lock before it has a live boss to supply a fight clock.
function M.update_hazard_pulses(dt)
    if not next(timed_pulses) then return end
    local Clock = require "mvtk.bosses.boss_clock"
    dt = Clock.delta(dt, Pause)
    if dt <= 0 then return end
    for token, pulse in pairs(timed_pulses) do
        local elapsed = dt
        if pulse.read_clock then
            local now = pulse.read_clock()
            if now then
                elapsed, pulse.last_time = now - pulse.last_time, now
            else
                pulse.read_clock = nil
            end
        end
        pulse.remaining = pulse.remaining - elapsed
        if Clock.reached(0, pulse.remaining) or not Pulse.is_running(token) then
            Pulse.stop(token)
            timed_pulses[token] = nil
        end
    end
end

--- Advance the live arena and apply its due phases in deadline order.
-- @param dt Delta time
function M.update(dt)
    M.update_hazard_pulses(dt)
    local arena = active_arena
    local elapsed = Clock.delta(dt, Pause)
    if not arena or elapsed <= 0 then return end
    local requests = arena.paused_phases
    arena.paused_phases = nil
    for _, request in ipairs(requests or {}) do
        M.transition_to_phase(request.phase, request.time, request.escalate)
    end
    arena.clock = arena.clock + elapsed
    apply_due_phases(arena)
end

-- ============================================================================
-- QUERY
-- ============================================================================

--- Get active arena
function M.get_active_arena()
    return active_arena
end

--- Get current phase
function M.get_current_phase()
    return active_arena and active_arena.current_phase or 0
end

--- Check if arena is locked
function M.is_locked()
    return active_arena and active_arena.locked or false
end

--- Check if in transition
function M.is_transitioning()
    return active_arena and active_arena.in_transition or false
end

--- Get arena bounds
function M.get_bounds()
    return active_arena and active_arena.bounds or nil
end

-- ============================================================================
-- TILED INTEGRATION
-- ============================================================================

--- Create arena configuration from Tiled properties.
-- Boss arenas now provide arena metadata only. Phase-driven hazards,
-- platforms, weak points, and other encounter pieces are authored as separate
-- Tiled objects that react to the arena's active phase.
-- @param properties Tiled object properties
-- @return Arena configuration
function M.create_from_tiled(properties)
    local config = {
        phases = {},
        hazard_configs = {},
        platform_configs = {},
    }

    local num_phases = tonumber(properties.phases) or 3

    -- Create empty phase slots so arena phase changes still work even when the
    -- encounter uses only object-driven arena pieces.
    for i = 1, num_phases do
        config.phases[i] = {}
    end

    -- Global settings
    if properties.camera_lock ~= nil then
        config.lock_camera = properties.camera_lock
    end

    local battle_music = optional_id(properties.battle_music) or optional_id(properties.combat_music)
    if battle_music then
        config.battle_music = battle_music
    end

    local victory_music = optional_id(properties.victory_music)
    if victory_music then
        config.victory_music = victory_music
    end

    return config
end

--- Activate hazards for a specific phase (called by enrage system)
-- @param phase Phase number
function M.activate_phase_hazards(phase)
    if not active_arena then return end

    local phase_config = active_arena.phases[phase]
    if not phase_config then return end

    -- Spawn hazards for this phase without clearing existing ones
    if phase_config.hazards then
        for _, hazard_id in ipairs(phase_config.hazards) do
            if not active_arena.active_hazards[hazard_id] then
                M.spawn_hazard(hazard_id)
            end
        end
    end

    log("Activated phase", phase, "hazards")
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

-- A new session (fresh start, another slot or Continue after quit to title)
-- starts with no arena active, so an arena left by a quit never locks fast
-- travel, shops or other rooms. Its world objects went with the previous
-- world, so only the record and the global effects are released.
function M.before_session_start()
    Pulse.clear_all()
    timed_pulses = {}
    release_global_effects()
    if active_arena then
        active_arena.locked, active_arena.current_phase = false, 0
        active_arena.effect_outputs = nil
        active_arena.phase_deadlines, active_arena.paused_phases = nil, nil
        active_arena.in_transition = false
    end
    active_arena = nil
end

function M.cleanup()
    Pulse.clear_all()
    timed_pulses = {}
    if active_arena then
        M.deactivate_arena()
    end
    for id in pairs(arenas) do
        require("mvtk.enemies.enemy_spawn_service").despawn_owner("arena:" .. id, "arena_cleanup")
    end
    arenas = {}
end

-- ============================================================================
-- COMPATIBILITY API
-- ============================================================================
-- Previously lived in mvtk/bosses/arena_mechanics.lua. That module is now a
-- thin wrapper forwarding to this module; these functions keep arena_mechanics
-- callers working without a parallel state store.

--- Register an arena. Alias for setup_arena that also returns the arena record.
function M.register_arena(arena_id, config)
    M.setup_arena(arena_id, config or {})
    return arenas[arena_id]
end

--- Lock an arena. Registers a minimal arena if the id is unknown so callers
--- that only need door-lock semantics (arena_lock.script) work without prior
--- setup_arena.
function M.lock_arena(arena_id)
    if not arenas[arena_id] then
        M.setup_arena(arena_id, {})
    end
    M.activate_arena(arena_id)
end

--- Unlock an arena. Deactivates the active arena if it matches; otherwise
--- clears the locked flag on the registered record.
function M.unlock_arena(arena_id)
    if active_arena and active_arena.id == arena_id then
        M.deactivate_arena()
        return
    end
    Pulse.clear(arena_id)
    local a = arenas[arena_id]
    if a then a.locked = false end
end

--- Get an arena record by id. Returns a shape compatible with the legacy
--- arena_mechanics `get_arena` return value (fields: id, locked, boss_active,
--- phase, bounds, config).
function M.get_arena(arena_id)
    local a = arenas[arena_id]
    if not a then return nil end
    return {
        id = a.id,
        locked = a.locked,
        boss_active = a.locked,
        phase = a.current_phase or 0,
        bounds = a.bounds,
        config = a,
    }
end

local function fight_clock(arena_id)
    local Bosses = require "mvtk.bosses.boss_manager"
    local boss_id = Bosses.find_boss_id({arena_id = arena_id})
    if not boss_id then return end
    return function()
        local boss = Bosses.get_boss(boss_id)
        return boss and not boss.defeated and (boss._boss_clock_at or boss.fight_time) or nil
    end
end

--- Trigger an ad-hoc arena effect.
--- effect_type: "screen_shake" | "flash" | "hazard_pulse" | "spawn_adds"
-- A hazard pulse can filter by a list of hazard_types and by pulse_only.
-- Omitting filters pulses the whole arena.
function M.trigger_arena_effect(arena_id, effect_type, params)
    local a = arenas[arena_id] or active_arena
    if not a then return end
    params = params or {}

    if effect_type == "screen_shake" then
        local Feedback = feedback()
        if Feedback then
            pcall(Feedback.screen_shake, params.duration, params.intensity or "heavy")
        end

    elseif effect_type == "flash" then
        local Feedback = feedback()
        if Feedback then
            pcall(Feedback.flash, {
                color = params.color or vmath.vector4(1, 1, 1, 0.5),
                duration = params.duration or 0.1,
            })
        end

    elseif effect_type == "hazard_pulse" then
        if arena_id and a.id ~= arena_id then return end
        local Schema = require "mvtk.bosses.attack_pattern_schema"
        local defaults = Util.require_config("developer.config.boss_defaults")
        local settings, err = Schema.hazard_pulse_options({
            type = "hazard_pulse",
            hazard_pulse = {warn_time = params.warn_time, duration = params.duration},
        }, defaults)
        if not settings then print("[BOSS_ARENA] " .. err); return end
        local read_clock = fight_clock(a.id)
        local started = read_clock and read_clock()
        local token = Pulse.start(a.id, nil, settings.warn_time, {
            hazard_types = params.hazard_types,
            pulse_only = params.pulse_only,
            elapsed = started and function() return (read_clock() or started) - started end,
        })
        if not token then return end
        timed_pulses[token] = {remaining = settings.warn_time + settings.duration,
            read_clock = read_clock, last_time = started}

    elseif effect_type == "spawn_adds" then
        local Spawn = require "mvtk.enemies.enemy_spawn_service"
        local bounds = a.bounds
        if bounds then
            -- Baked arenas use x/y and size. Configured arenas can use corners.
            local x = tonumber(bounds.x or bounds.min_x)
            local y = tonumber(bounds.y or bounds.min_y)
            if not (x and y) then return end
            local width = tonumber(bounds.width) or (tonumber(bounds.max_x) or x) - x
            local height = tonumber(bounds.height) or (tonumber(bounds.max_y) or y) - y
            local count = params.count or 3
            local defaults = require("developer.config.runtime_settings").section("enemy_defaults", require "developer.config.enemy_defaults")
            local enemy_type = params.enemy_type or defaults.default_archetype
            local radius = params.spawn_radius or 200
            local cx, cy = x + width / 2, y + height / 2
            for i = 1, count do
                local angle = (math.pi * 2 / count) * i
                local pos = vmath.vector3(cx + math.cos(angle) * radius,
                                          cy + math.sin(angle) * radius, 0)
                Spawn.spawn({owner = "arena:" .. a.id, room_id = a.room_id,
                    enemy_type = enemy_type, position = pos})
            end
        end

    end

    log("Triggered effect", effect_type, "on arena", arena_id)
end

return M
