-- Transient session service. Event listeners only change module-local state.
local Events = require "mvtk.core.game_events"
local M = {}
local state, hit, requested = {}, false, false
local cached_config, cached_revision

local function frame_config()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local revision = RuntimeSettings.revision()
    if not cached_config or cached_revision ~= revision then
        cached_config = RuntimeSettings.section("combat_music", require "developer.config.combat_music")
        cached_revision = revision
    end
    return cached_config
end

-- True when two points are less than a pixel apart, too close for a ray.
local function same_spot(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return dx * dx + dy * dy < 1
end

-- Pure value transition: no engine calls, mutation of inputs or shared state.
-- A nil output means no layer change. Pausing holds the entire machine.
function M.step(previous, dt, view, cfg)
    local s = {}
    for k, v in pairs(previous) do s[k] = v end
    local changed_room = s.room ~= view.room
    if changed_room then
        s = {room=view.room, phase="quiet", elapsed=0, quiet=0, revision=view.revision}
    end
    if not changed_room and (view.requested or (s.revision ~= nil and s.revision ~= view.revision)) then
        s.blocked = true
    end
    s.revision = view.revision
    if view.paused then
        if changed_room and previous.track then
            return s, {track=previous.track, active=false, t=cfg.fade_out}
        end
        return s
    end
    local track = view.track
    local was = previous.track
    if not cfg.enabled or not view.room or not view.playing or view.boss or view.locked or s.blocked or not track then
        s.phase, s.elapsed, s.quiet, s.track = "quiet", 0, 0, nil
    else
        local nearby = (view.count or 0) >= cfg.engage.count
        local struck = view.hit and cfg.engage.on_player_hit
        if s.phase == "quiet" or s.phase == nil then
            s.elapsed = nearby and ((s.elapsed or 0) + dt) or 0
            if struck or (nearby and s.elapsed >= cfg.engage.min_time) then
                s.phase, s.track, s.quiet = "engaged", track, 0
            end
        elseif nearby or struck then
            s.phase, s.quiet, s.track = "engaged", 0, track
        else
            s.phase, s.quiet = "releasing", (s.quiet or 0) + dt
            if s.quiet >= cfg.release_delay then
                s.phase, s.elapsed, s.quiet, s.track = "quiet", 0, 0, nil
            end
        end
    end
    -- Room music may have cleared the controller even when the new room
    -- immediately engages the same combat id.
    if s.track ~= was or (changed_room and s.track ~= nil) then
        return s, {track=s.track or was, active=s.track ~= nil, t=s.track and cfg.fade_in or cfg.fade_out}
    end
    return s
end

function M.resolve_track(value, cfg, aliases)
    value = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
    if value == "" or value == "inherit" then value = cfg.default_track end
    if value == "" or value == "none" then return nil end
    local alias = (aliases or {})[value]
    return alias and alias.cue and alias.cue:match("/([^/]+)%.sound$") or value
end

-- Also called for messages sent directly to the controller, bypassing Audio.
function M.music_requested(request_revision)
    -- Facade requests were already observed through music_request_revision.
    -- Their queued messages can arrive after the room transition's first tick.
    if request_revision ~= nil then return end
    requested = true
    require("mvtk.audio.audio").clear_combat_theme()
end

function M.update(dt)
    local cfg = frame_config()
    -- No streaming/enemy dependency is loaded by an idle, disabled service.
    if not cfg.enabled and not state.track then hit, requested = false, false; return end
    local Audio = require "mvtk.audio.audio"
    local room = require("mvtk.map.streaming.room_manager").get_current_room()
    local Game = require "mvtk.game.game_manager"
    local paused = require("mvtk.core.pause").get()
    local playing = Game.get_state() == Game.STATE.PLAYING
    local boss = require("mvtk.bosses.boss_music").is_playing()
    local locked = require("mvtk.bosses.fight_lock").is_locked(room)
    local props = require("mvtk.tiled.tiled_room_registry").get_room_metadata(room).authored_properties or {}
    local track = M.resolve_track(props.combat_music, cfg, require "developer.config.ambience_tracks")
    local revision = Audio.music_request_revision()
    local blocked = state.room == room and (state.blocked or requested or
        (state.revision ~= nil and state.revision ~= revision))
    local count, pos = 0, rawget(_G, "PLAYER_WORLD_POS")
    if cfg.enabled and room and playing and not paused and not boss and not locked and not blocked and pos and track then
        for _, entry in ipairs(require("mvtk.enemies.enemy_manager").get_enemies_in_range(pos, cfg.engage.radius)) do
            local enemy = entry.enemy
            if enemy.alive and enemy.room_id == room and
                (not cfg.ignore_spawned or require("mvtk.enemies.enemy_spawn_service").outcome(enemy.id) == nil) then
                -- Both positions are actor origins above their feet, not floor
                -- points. Reuse detection's terrain groups, including platforms.
                -- An enemy on the player's own origin, such as a homing fly, is
                -- in sight: Box2D refuses a ray whose ends meet and warns on
                -- every frame it is asked (Stage 9 A46).
                if cfg.engage.line_of_sight == false or same_spot(pos, enemy.position)
                    or physics.raycast(pos, enemy.position,
                    require("mvtk.core.surface_classifier").RAYCAST.TERRAIN) == nil then
                    count = count + 1
                    -- The distance-sorted list only needs to meet the threshold.
                    if count >= cfg.engage.count then break end
                end
            end
        end
    end
    local output
    state, output = M.step(state, dt, {room=room, track=track, count=count, playing=playing,
        paused=paused, boss=boss, locked=locked, hit=hit, requested=requested,
        revision=revision}, cfg)
    hit, requested = false, false
    if output and (output.active or Audio.combat_theme()) then
        Audio.set_combat_theme(output.track, output.active, output.t)
    end
end

-- Controller calls this bridge once per frame; pause holds combat timers and
-- its audible fade. Pending layer requests survive crossfade debounce.
function M.tick_controller(controller, dt)
    M.update(dt)
    if controller._combat_fade and frame_config().enabled and require("mvtk.core.pause").get() then return true end
    require("mvtk.audio.music_crossfade").update_layer(controller)
end

function M.on_session_start()
    -- Retain only a previously owned layer so the next tick can release it.
    state, hit, requested = {track=state.track}, false, false
    cached_config, cached_revision = nil, nil
end

Events.on("enemy_damaged", function(payload)
    if payload.by_player == true and payload.boss == false then hit = true end
end)
return M
