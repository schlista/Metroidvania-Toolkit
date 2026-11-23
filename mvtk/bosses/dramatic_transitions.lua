-- mvtk/bosses/dramatic_transitions.lua
-- Dramatic boss phase transition system
-- Creates memorable moments when bosses change phases

local Motion = require "mvtk.bosses.boss_motion"
local M = {}
local Pause = require "mvtk.core.pause"

local Util = require "mvtk.core.util"
local Hitstop = Util.require_module("mvtk.fx.hitstop")
local BossArena = Util.require_module("mvtk.bosses.boss_arena")
local Audio = Util.require_module("mvtk.audio.audio")

local Cues = require("mvtk.bosses.transition_cues").resolve(
    Util.require_config("developer.config.boss_defaults", {}))
local Defaults = Cues.dramatic
local TRANSITION_TYPES = Util.deep_copy(Defaults.presets)

--- Execute a dramatic phase transition
-- @param boss_url Boss game object URL
-- @param transition_type Type of transition
-- @param options Custom options to override preset
-- @param on_complete Callback when transition finishes
function M.execute_transition(boss_url, transition_type, options, on_complete)
    if Pause.get() then
        Pause.delay(0, function()
            if go.exists(boss_url) then M.execute_transition(boss_url, transition_type, options, on_complete) end
        end)
        return
    end
    local preset = TRANSITION_TYPES[transition_type] or TRANSITION_TYPES.standard
    options = options or {}

    -- Merge options with preset
    local config = {}
    for k, v in pairs(preset) do
        config[k] = v
    end
    for k, v in pairs(options) do
        config[k] = v
    end

    print(string.format("[DRAMATIC_TRANSITIONS] Executing '%s' transition", transition_type))

    -- Step 1: Hitstop
    if config.hitstop_duration and config.hitstop_duration > 0 then
        Hitstop.start_hitstop(config.hitstop_duration, config.shake_intensity, nil, true)
    end

    -- Steps 2 and 3: camera shake and screen flash through the live owners.
    local Feedback = Util.require_module("mvtk.combat.combat_feedback")
    if Feedback and config.shake_intensity and Cues.shake_enabled ~= false then
        pcall(Feedback.screen_shake, config.shake_duration, config.shake_intensity)
    end
    if Feedback and config.flash_color and config.flash_duration and config.flash_duration > 0
        and Cues.flash_enabled ~= false then
        local color = config.flash_color
        if type(color) == "table" and color[1] then
            color = vmath.vector4(color[1], color[2], color[3], color[4])
        end
        pcall(Feedback.flash, {
            color = color,
            duration = config.flash_duration
        })
    end

    -- Step 4: Boss effects
    Pause.delay(Defaults.effects_delay, function()
        if not go.exists(boss_url) then
            if on_complete then on_complete() end
            return
        end

        -- Scale pulse effect
        if config.boss_scale_pulse then
            local original_scale = go.get_scale(boss_url)
            Motion.scale(boss_url,
                original_scale * config.boss_scale_pulse,
                Defaults.scale_duration, "out_quad", true)
        end

        -- Disappear/reappear
        if config.boss_disappear then
            local base_scale = Motion.get_base_scale(boss_url)
            -- Shrink to disappear
            Motion.scale(boss_url,
                Motion.disappear_scale(base_scale),
                Defaults.scale_duration, "in_cubic", false, function()

                -- Teleport to new position if specified
                if config.teleport_destination then
                    local new_pos = config.teleport_destination
                    if type(new_pos) == "function" then
                        new_pos = new_pos()
                    end
                    if new_pos and new_pos ~= true then
                        go.set_position(new_pos, boss_url)
                    end
                end

                -- Reappear after delay
                Pause.delay(config.boss_reappear_delay or Defaults.reappear_delay, function()
                    if go.exists(boss_url) then
                        Motion.scale(boss_url, base_scale, Defaults.scale_duration, "out_cubic")

                        -- Reappear particles
                        if config.spawn_particles == "teleport_out" then
                            -- Spawn teleport in effect
                        end
                    end
                end)
            end)
        end

        -- Invulnerability
        if config.boss_invulnerable then
            pcall(msg.post, boss_url, "set_invulnerable", {
                duration = config.pause_duration or Defaults.pause_duration
            })
        end

        -- Spawn particles
        if config.spawn_particles and go.exists(boss_url) then
            local pos = go.get_position(boss_url)
            -- Trigger particle effect at boss position
            -- This would need a particle factory
            pcall(msg.post, "#particle_factory", "spawn_effect", {
                effect_type = config.spawn_particles,
                position = pos
            })
        end

        -- Spawn adds
        if config.spawn_adds then
            local arena_id = options.arena_id
            if arena_id then
                BossArena.trigger_arena_effect(arena_id, "spawn_adds", {
                    count = options.add_count or 3,
                    enemy_type = options.add_type or "slime",
                    spawn_radius = options.spawn_radius or 200
                })
            end
        end

        -- Pulse every type of placed hazard that opts into transitions.
        if config.activate_hazards then
            local arena_id = options.arena_id
            if arena_id then
                BossArena.trigger_arena_effect(arena_id, "hazard_pulse", {pulse_only = true})
            end
        end

        -- Music change
        if config.music_change and options.new_music then
            Audio.music(options.new_music, {
                -- track removed, passed as first arg
                t = Defaults.music_fade
            })
        end
    end)

    -- Step 5: Complete after pause duration
    if config.pause_duration then
        Pause.delay(config.pause_duration, function()
            if on_complete then
                on_complete()
            end
        end)
    else
        if on_complete then
            on_complete()
        end
    end
end

--- Create a custom transition type
-- @param name Transition name
-- @param config Transition configuration
function M.register_transition_type(name, config)
    TRANSITION_TYPES[name] = config
    print(string.format("[DRAMATIC_TRANSITIONS] Registered custom transition '%s'", name))
end

--- Get transition preset
-- @param transition_type Type name
-- @return Transition configuration or nil
function M.get_preset(transition_type)
    return TRANSITION_TYPES[transition_type]
end

--- Execute quick transition without full ceremony
-- @param boss_url Boss game object URL
-- @param intensity "light", "medium", "heavy"
function M.quick_transition(boss_url, intensity)
    intensity = intensity or "medium"

    if intensity == "light" then
        Hitstop.on_hit_light()
    elseif intensity == "heavy" then
        Hitstop.on_hit_heavy()
    else
        Hitstop.on_hit_medium()
    end
    local Feedback = Util.require_module("mvtk.combat.combat_feedback")
    if Feedback and Cues.shake_enabled ~= false then
        pcall(Feedback.screen_shake, nil, intensity)
    end

    print("[DRAMATIC_TRANSITIONS] Quick transition executed")
end

return M
