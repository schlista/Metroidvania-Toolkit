-- mvtk/game/game_manager.lua
-- ============================================================================
-- Game Manager - Global State Coordinator
-- ============================================================================
-- Central system managing game state transitions and coordinating high-level
-- game flow. Handles state changes between menus, gameplay, pause, and game over.
--
-- Game States:
--   INITIALIZING - Game is starting up (transitional)
--   MAIN_MENU - At main menu (not playing)
--   PLAYING - Active gameplay
--   PAUSED - Game paused (can resume)
--   GAME_OVER - Player died (can restart)
--   LOADING - Loading new content (transitional)
--
-- State Callbacks:
--   Register callbacks to be notified when specific states are entered.
--   Useful for UI updates, audio changes, input blocking, etc.
--
-- Usage:
--   GameManager.init()
--   GameManager.set_state(GameManager.STATE.PLAYING)
--   GameManager.register_state_callback(GameManager.STATE.PAUSED, function() ... end)

local C = require "mvtk.core.constants"
local Util = require "mvtk.core.util"
local Debug = Util.require_config("developer.config.debug_config", { global = {}, gameplay = {} })
local Logger = require("mvtk.core.logger")

-- ============================================================================
-- DEBUG LOGGING
-- ============================================================================

-- Create module-specific logger
local log = Logger.get_logger("GAME_MANAGER")

-- Conditional logging for game manager events (only if debug enabled)
local function gm_log(...)
    if (Debug.global and Debug.global.enable) or (Debug.gameplay and Debug.gameplay.game_manager) then
        log.debug(...)
    end
end

local M = {}
local Config = Util.require_config("developer.config.resolved_config")
local LayoutIO = require "mvtk.rooms.layout_io"
local RoomManager = require "mvtk.map.streaming.room_manager"
local ElevatorManager = require "mvtk.elevators.elevator_manager"
local DeathDrop = require "mvtk.game.death_drop"
local EnemySpawnService = require "mvtk.enemies.enemy_spawn_service"
local EnemyDefeats = require "mvtk.enemies.enemy_defeats"
local Pause = require "mvtk.core.pause"
local PlayerStats = require "mvtk.player.player_stats"
local RunStats = require "mvtk.game.run_stats"
local Countdown = require "mvtk.game.countdown"
local StatusEffects = require "mvtk.combat.status_effects"

-- ============================================================================
-- GAME STATES
-- ============================================================================

-- Available game states (use these constants instead of strings)
M.STATE = {
    INITIALIZING = "initializing",  -- Game starting up
    MAIN_MENU = "main_menu",  -- At main menu
    PLAYING = "playing",  -- Active gameplay
    PAUSED = "paused",  -- Game paused
    GAME_OVER = "game_over",  -- Player died
    LOADING = "loading"  -- Loading content
}

-- Current game state (starts as INITIALIZING)
local current_state = M.STATE.INITIALIZING
local lifetime = 0
-- State callbacks are cleared by final; persistent services reattach per lifetime.
function M.lifetime() return lifetime end

-- LOADING-state watchdog: if the game enters LOADING and never transitions
-- back inside LOAD_TIMEOUT_S, M.update(dt) emits a one-shot warning so the
-- developer notices a hang (e.g. a room preparation never completed). The
-- watchdog only logs; it does not force a state transition.
local LOAD_TIMEOUT_S = 15.0
local loading_started_at = nil
local loading_warned = false

-- Guard flag to prevent overlapping respawn arrivals.
local restart_in_progress = false
local restart_generation = 0

local function reset_elevators_for_player_lifecycle(reason)
    local ok, result = pcall(ElevatorManager.on_player_death)
    if not ok then
        log.error("Failed to reset elevators for %s: %s", tostring(reason), tostring(result))
    end
    return ok, result
end

-- Callback registry: {state_name = {callback1, callback2, ...}}
-- Callbacks are called when entering their registered state
local state_callbacks = {}

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

-- Initialize the game manager system
-- settings: Optional settings table (reserved for future use)
--
-- Call this once at game startup to initialize the state system.
-- Automatically transitions to MAIN_MENU state.
function M.init(settings)
    DeathDrop.init(M.is_playing)
    EnemySpawnService.init()
    EnemyDefeats.init()
    require("mvtk.combat.hit_reactions").init()
    gm_log("[GAME_MANAGER] Initializing game manager system...")

    -- Set initial state (main menu)
    M.set_state(M.STATE.MAIN_MENU)

    gm_log("[GAME_MANAGER] Game manager system initialized")
end

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

-- Get the current game state
-- Returns: One of the M.STATE constants (string)
function M.get_state()
    return current_state
end

-- Change the game state
-- new_state: One of the M.STATE constants
--
-- Triggers all callbacks registered for the new state.
-- Does nothing if new_state equals current state (no redundant transitions).
function M.set_state(new_state)
    if new_state == current_state then
        return  -- No change needed
    end

    local old_state = current_state
    current_state = new_state

    -- Watchdog bookkeeping: stamp on entry to LOADING, clear on exit.
    if new_state == M.STATE.LOADING then
        loading_started_at = (socket and socket.gettime and socket.gettime()) or os.clock()
        loading_warned = false
    elseif old_state == M.STATE.LOADING then
        loading_started_at = nil
        loading_warned = false
    end

    gm_log(string.format("[GAME_MANAGER] State changed: %s -> %s", old_state, new_state))

    -- Trigger state change callbacks for the new state
    if state_callbacks[new_state] then
        for _, callback in ipairs(state_callbacks[new_state]) do
            if type(callback) == "function" then
                -- Protected call to prevent one callback from breaking others
                pcall(callback, old_state, new_state)
            end
        end
    end
end

-- Register a callback to be called when entering a specific state
-- state: One of the M.STATE constants
-- callback: Function(old_state, new_state) to call on state entry
--
-- Example:
--   GameManager.register_state_callback(GameManager.STATE.PAUSED, function()
--     InputController.set_blocked(true)  -- Block input when paused
--   end)
function M.register_state_callback(state, callback)
    if not state_callbacks[state] then
        state_callbacks[state] = {}
    end
    table.insert(state_callbacks[state], callback)
end

-- ============================================================================
-- GAME EVENTS
-- ============================================================================

-- Compute a safe spawn position when no checkpoint exists.
local function compute_default_spawn(layout)
    local force = Config.player and Config.player.force_spawn
    if force and force.enabled then
        return vmath.vector3(force.x or 0, force.y or 0, 0)
    end

    if layout and layout.rooms and #layout.rooms > 0 then
        local first = layout.rooms[1]
        if first and tonumber(first.x) and tonumber(first.y) and tonumber(first.w) and tonumber(first.h) then
            local bounds = require("mvtk.map.streaming.room_geometry").make_room_bounds(first)
            local cx = (bounds.min_x + bounds.max_x) * 0.5
            local cy = (bounds.min_y + bounds.max_y) * 0.5
            return vmath.vector3(cx, cy, 0)
        end
    end

    -- Fallback to a conservative default
    return vmath.vector3(300, 400, 0)
end

-- Handle player death event
-- Transitions to GAME_OVER state and shows death screen.
-- Call this when player health reaches zero.
function M.handle_player_death()
    log.info("💀 HANDLE_PLAYER_DEATH called")

    -- Persistent cabins survive streamed-room teardown, so invalidate active
    -- trips and return them home before the death screen takes control.
    reset_elevators_for_player_lifecycle("player_death")
    StatusEffects.reset()
    
    -- Set state to game over
    gm_log("Setting state to GAME_OVER...")
    local ok_state, err_state = pcall(function() M.set_state(M.STATE.GAME_OVER) end)
    if ok_state then
        gm_log("State set successfully")
    else
        log.error("Failed to set state: %s", tostring(err_state))
    end
    
    gm_log("Player died, transitioning to game over state")

    -- Show death GUI (safe post in case GUI not loaded)
    pcall(msg.post, "main:/list_menu_gui#list_menu", "close_list_menu", { reason = "death" })
    local death_gui_url = msg.url("main:/death_gui#death")
    gm_log("Sending 'open_death' message to: %s", tostring(death_gui_url))
    local ok, err = pcall(msg.post, death_gui_url, hash("open_death"), {})
    if ok then
        gm_log("Death GUI message sent successfully")
    else
        log.warn("Failed to send death GUI message: %s", tostring(err))
    end
    gm_log("handle_player_death completed")
end

-- Handle game restart event
-- Transitions through LOADING state back to PLAYING.
-- Call this when player chooses to restart after death.
function M.handle_restart()
    -- Guard against stacking restart calls
    if restart_in_progress then
        gm_log("Restart already in progress, ignoring duplicate call")
        return
    end
    restart_in_progress = true
    restart_generation = restart_generation + 1

    -- Restart may be requested independently of the ordinary death event.
    -- Place this behind the duplicate guard so each accepted restart resets
    -- elevator generations exactly once.
    reset_elevators_for_player_lifecycle("restart")
    StatusEffects.reset()
    
    log.info("🔄 RESTART GAME CALLED")
    gm_log("Restarting game...")
    M.set_state(M.STATE.LOADING)

    local player_url = C.URL and C.URL.PLAYER
    -- Resource readiness, rather than a timer, determines when the player
    -- comes back to life. Keep checkpoint preparation in this call.
    do
        local Checkpoint = require "mvtk.core.checkpoint"
        
        -- Clear stale parallax layers from previous room state
        local ParallaxOk, ParallaxManager = pcall(require, "mvtk.tiled.parallax_layer_manager")
        if ParallaxOk and ParallaxManager and ParallaxManager.clear_all then
            gm_log("Clearing stale parallax layers...")
            ParallaxManager.clear_all()
        end
        
        gm_log("========== RESPAWN CHECKPOINT LOADING ==========")
        
        -- Restart restores the test-session memory save when active; ordinary
        -- play and End test session restore the last real save.
        gm_log("Loading latest checkpoint snapshot...")
        local load_ok = Checkpoint.load(Checkpoint.slot or 1, { keep_session_clock = true })
        require("mvtk.player.assist").after_restart_load(load_ok)
        local penalty_ok = DeathDrop.after_checkpoint_load(load_ok)
        RunStats.after_restart_load(load_ok, penalty_ok)
        if not penalty_ok then M.finish_restart(restart_generation, false); return end
        if load_ok then EnemyDefeats.world_reset("respawn") end
        if load_ok then
            gm_log("✅ Checkpoint loaded successfully")
        else
            gm_log("⚠️ Failed to load checkpoint snapshot")
        end
        
        -- Debug: Print checkpoint data structure
        gm_log("Checkpoint.data type: %s", type(Checkpoint.data))
        if Checkpoint.data then
            gm_log("Checkpoint.data.checkpoint type: %s", type(Checkpoint.data.checkpoint))
            if Checkpoint.data.checkpoint then
                gm_log("Checkpoint.data.checkpoint = {x=%.1f, y=%.1f, room_id=%s}",
                    Checkpoint.data.checkpoint.x or -999,
                    Checkpoint.data.checkpoint.y or -999,
                    tostring(Checkpoint.data.checkpoint.room_id or "nil"))
            end
        end
        
        -- Resolve position and room together so arrival validates the same bounds.
        local cp = Checkpoint.data and Checkpoint.data.checkpoint
        local layout = LayoutIO and LayoutIO.load and LayoutIO.load({ runtime_preferred = true }) or {}
        local resolved, reason = require("mvtk.world.checkpoint_return").resolve(cp, layout)
        local target_pos, room_id, position_kind
        if resolved then
            target_pos, room_id = resolved.position, resolved.room_id
            position_kind = resolved.position_kind
        else
            gm_log("Checkpoint unavailable (%s) - using default spawn", tostring(reason))
            target_pos = compute_default_spawn(layout)
            Checkpoint.data = Checkpoint.data or {}
            position_kind = "feet"
            Checkpoint.data.checkpoint = { x = target_pos.x, y = target_pos.y, position_kind = position_kind }
            -- No room hint: arrival infers the fallback room from runtime bounds.
        end

        pcall(Checkpoint.apply, player_url, { skip_position = true })

        if player_url and go.exists(player_url) then
            local posted = pcall(msg.post, player_url, C.MSG and C.MSG.RESTORE_HEALTH or hash("mvtk_restore_health"), {
                respawn_pos = target_pos, room_id = room_id, restart_request = restart_generation, reason = "respawn",
                position_kind = position_kind,
                respawn_grace = math.max(0, tonumber(Config.player and Config.player.respawn and Config.player.respawn.iframes) or 0.5),
            })
            if not posted then M.finish_restart(restart_generation, false) end

            -- Reset enemy detection system
            local DetectionOk, Detection = pcall(require, "mvtk.enemies.detection")
            if DetectionOk and Detection.reset then
                gm_log("Resetting enemy detection...")
                Detection.reset()
            end
        else
            M.finish_restart(restart_generation, false)
        end
        log.info("Player respawn queued for room readiness")
    end
end

function M.finish_restart(request, success)
    if not restart_in_progress or request ~= restart_generation then return false end
    restart_in_progress = false
    if success then
        M.set_state(M.STATE.PLAYING)
    else
        M.set_state(M.STATE.GAME_OVER)
        pcall(msg.post, (C.URL and C.URL.DEATH_GUI) or "main:/death_gui#death", hash("open_death"), {})
    end
    return true
end

-- Toggle between PLAYING and PAUSED states
-- Call this when player presses pause button.
-- Ignores toggle if in other states (e.g., can't pause at main menu).
function M.handle_pause_toggle()
    if current_state == M.STATE.PLAYING then
        M.set_state(M.STATE.PAUSED)
    elseif current_state == M.STATE.PAUSED then
        M.set_state(M.STATE.PLAYING)
    end
    -- Ignore if in other states
end

-- ============================================================================
-- QUERY FUNCTIONS
-- ============================================================================

-- Check if game is currently in PLAYING state
-- Returns: true if playing, false otherwise
function M.is_playing()
    return current_state == M.STATE.PLAYING
end

-- Check if game is currently in PAUSED state
-- Returns: true if paused, false otherwise
function M.is_paused()
    return current_state == M.STATE.PAUSED
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================

-- Update game manager each frame
-- dt: Delta time in seconds
--
-- Drives the LOADING-state watchdog so a stuck transition surfaces a
-- warning in the console rather than silently hanging at a black screen.
function M.update(dt)
    DeathDrop.update(dt)
    PlayerStats.tick(dt, current_state == M.STATE.PLAYING and not Pause.get())
    RunStats.tick(dt, current_state == M.STATE.PLAYING and not Pause.get())
    Countdown.tick(dt, current_state == M.STATE.PLAYING and not Pause.get())
    if current_state == M.STATE.PLAYING and not Pause.get() then StatusEffects.update(dt) end
    if current_state == M.STATE.LOADING and loading_started_at and not loading_warned then
        local now = (socket and socket.gettime and socket.gettime()) or os.clock()
        if (now - loading_started_at) >= LOAD_TIMEOUT_S then
            loading_warned = true
            gm_log(string.format("[GAME_MANAGER] WARN: still in LOADING after %.1fs; check for missed transition",
                LOAD_TIMEOUT_S))
        end
    end
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

-- Clean up game manager system
-- Call this when shutting down the game or resetting to initial state.
function M.final()
    local fights = package.loaded["mvtk.game.fight_session"]
    if fights and fights.reset_lifetime then fights.reset_lifetime() end
    Countdown.reset_lifetime()
    require("mvtk.core.profile_store").flush(true)
    DeathDrop.final()
    EnemySpawnService.final()
    EnemyDefeats.final()
    -- Room-unload subscribers that RoomManager.final drops must subscribe again.
    for _, name in ipairs({ "mvtk.combat.hit_reactions", "mvtk.npcs.npc_manager" }) do
        local module = package.loaded[name]
        if type(module) == "table" and module.final then module.final() end
    end
    -- Run-wide tables that hold this world's objects or state: the next session
    -- reuses its object paths, so none of it may carry over.
    for name, reset in pairs({ ["mvtk.world.trigger_bus"] = "clear", ["mvtk.rooms.tilemap_layers"] = "clear_urls",
        ["mvtk.rooms.door_state"] = "clear_listeners",
        ["mvtk.audio.audio"] = "forget_music_request", ["mvtk.collectibles.hidden_pickup_notice"] = "reset", ["mvtk.player.assist"] = "end_session" }) do
        local module = package.loaded[name]
        if type(module) == "table" and type(module[reset]) == "function" then module[reset]() end
    end
    StatusEffects.reset()
    gm_log("[GAME_MANAGER] Cleaning up game manager system...")
    state_callbacks = {}
    lifetime = lifetime + 1
    current_state = M.STATE.INITIALIZING
    restart_in_progress = false
end

return M
