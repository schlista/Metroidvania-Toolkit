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

-- ============================================================================
-- DATA STRUCTURES
-- ============================================================================

local arenas = {}           -- arena_id -> arena_data
local active_arena = nil

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
        transition_timer = 0,
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

    active_arena = arena
    arena.locked = true
    arena.current_phase = 0

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
    require("mvtk.enemies.enemy_spawn_service").despawn_owner("arena:" .. active_arena.id, "arena_deactivated")

    -- Clear all hazards and platforms
    M.clear_all_hazards()
    M.clear_all_platforms()
    M.clear_all_effects()

    -- Unlock doors
    M.unlock_doors(active_arena)

    active_arena.locked = false
    active_arena.current_phase = 0

    log("Deactivated arena:", active_arena.id)
    active_arena = nil
end

-- ============================================================================
-- PHASE MANAGEMENT
-- ============================================================================

--- Transition to a new phase
-- @param phase_number Phase number to transition to
-- @param transition_time Optional transition duration
-- @param escalate_only Optional monotonic application for a grouped encounter
function M.transition_to_phase(phase_number, transition_time, escalate_only)
    if Pause.get() then
        local arena = active_arena
        Pause.delay(0, function()
            if active_arena == arena then M.transition_to_phase(phase_number, transition_time, escalate_only) end
        end)
        return
    end
    if not active_arena then return end

    local phase_config = active_arena.phases[phase_number]
    if not phase_config then
        log("WARNING: Phase", phase_number, "not configured")
        return
    end

    transition_time = transition_time or phase_config.transition_time or 1.0

    log("Transitioning to phase", phase_number)

    active_arena.in_transition = true
    active_arena.transition_timer = transition_time

    -- Callback for phase change
    if active_arena.on_phase_change then
        active_arena.on_phase_change(active_arena.current_phase, phase_number)
    end

    -- Start transition effects
    if phase_config.transition_effect then
        M.play_transition_effect(phase_config.transition_effect)
    end

    -- Schedule phase application
    local arena = active_arena
    Pause.delay(transition_time, function()
        -- Group requests may have different authored transition durations. An
        -- older callback must never undo an already-applied higher boss phase.
        if active_arena == arena and (not escalate_only or phase_number > (arena.current_phase or 0)) then
            M.apply_phase(phase_number)
        end
    end)
end

--- Apply a phase configuration
-- @param phase_number Phase number to apply
function M.apply_phase(phase_number)
    if not active_arena then return end

    local phase_config = active_arena.phases[phase_number]
    if not phase_config then return end

    active_arena.current_phase = phase_number
    active_arena.in_transition = false

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

--- Apply an arena effect
-- @param effect_id Effect identifier
function M.apply_effect(effect_id)
    if not active_arena then return end

    local effect_fn = M.effect_handlers[effect_id]
    if effect_fn then
        effect_fn(active_arena)
        active_arena.active_effects[effect_id] = true
        log("Applied effect:", effect_id)
    end
end

--- Remove an arena effect
-- @param effect_id Effect identifier
function M.remove_effect(effect_id)
    if not active_arena then return end

    local remove_fn = M.effect_removers[effect_id]
    if remove_fn then
        remove_fn(active_arena)
    end

    active_arena.active_effects[effect_id] = nil
    log("Removed effect:", effect_id)
end

--- Clear all effects
function M.clear_all_effects()
    if not active_arena then return end

    for effect_id, _ in pairs(active_arena.active_effects) do
        M.remove_effect(effect_id)
    end
end

-- Effect handlers
M.effect_handlers = {
    screen_shake = function(arena)
        local Feedback = feedback()
        if Feedback then pcall(Feedback.screen_shake, nil, "light") end
    end,

    darkness = function(arena)
        pcall(msg.post, "main:/light_manager#script", hash("set_darkness"), {level = 0.7})
    end,

    slow_motion = function(arena)
        Pause.set_speed_factor("arena_slow_motion", 0.5)
        M._slow_motion_active = true
    end,

    low_gravity = function(arena)
        M.set_gravity(0.5)
    end,

    high_gravity = function(arena)
        M.set_gravity(1.5)
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

    darkness = function(arena)
        pcall(msg.post, "main:/light_manager#script", hash("set_darkness"), {})
    end,

    slow_motion = function(arena)
        Pause.set_speed_factor("arena_slow_motion", nil)
        M._slow_motion_active = nil
    end,

    low_gravity = function(arena)
        M.set_gravity(1.0)
    end,

    high_gravity = function(arena)
        M.set_gravity(1.0)
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
    -- Update any boundary-dependent systems
end

--- Set gravity
function M.set_gravity(scale)
    local Stats = require "mvtk.player.player_stats"
    if scale == 1 then Stats.clear_source("arena:gravity")
    else Stats.set_source("arena:gravity", {gravity_mult=scale}, {layer="temporary"}) end
end

--- Set darkness level
function M.set_darkness(level)
    pcall(msg.post, "main:/light_manager#script", hash("set_darkness"), {level = level})
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

--- Update arena system
-- @param dt Delta time
function M.update(dt)
    if not active_arena then return end

    -- Update transition
    if active_arena.in_transition then
        active_arena.transition_timer = active_arena.transition_timer - dt
    end
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
    release_global_effects()
    if active_arena then active_arena.locked, active_arena.current_phase = false, 0 end
    active_arena = nil
end

function M.cleanup()
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

--- Trigger an ad-hoc arena effect.
--- effect_type: "screen_shake" | "flash" | "hazard_pulse" | "spawn_adds" | "moving_platforms"
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
        for _, hazard in pairs(a.active_hazards or {}) do
            for _, go_id in ipairs(hazard.game_objects or {}) do
                if go.exists(go_id) then
                    pcall(msg.post, go_id, "pulse_activate")
                end
            end
        end

    elseif effect_type == "spawn_adds" then
        local Spawn = require "mvtk.enemies.enemy_spawn_service"
        local bounds = a.bounds
        if bounds then
            local count = params.count or 3
            local defaults = require("developer.config.runtime_settings").section("enemy_defaults", require "developer.config.enemy_defaults")
            local enemy_type = params.enemy_type or defaults.default_archetype
            local radius = params.spawn_radius or 200
            local cx = bounds.x + (bounds.width or 0) / 2
            local cy = bounds.y + (bounds.height or 0) / 2
            for i = 1, count do
                local angle = (math.pi * 2 / count) * i
                local pos = vmath.vector3(cx + math.cos(angle) * radius,
                                          cy + math.sin(angle) * radius, 0)
                Spawn.spawn({owner = "arena:" .. a.id, room_id = a.room_id,
                    enemy_type = enemy_type, position = pos})
            end
        end

    elseif effect_type == "moving_platforms" then
        pcall(msg.post, "/arena_platforms#" .. tostring(arena_id), "activate_movement")
    end

    log("Triggered effect", effect_type, "on arena", arena_id)
end

return M
