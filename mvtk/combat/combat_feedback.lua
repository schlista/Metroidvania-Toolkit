-- mvtk/combat/combat_feedback.lua
-- Single owner for combat feedback: hitstop, shake, rumble, and SFX.

local Util = require "mvtk.core.util"
local CombatConfig = require "mvtk.combat.config"
-- Literal require: a named load ran before Gamefeel was registered in export
-- builds and stayed nil all session (AUDIT_BUILD_BUNDLING row 3).
local Gamefeel = require "mvtk.core.gamefeel"
local Audio = Util.require_module("mvtk.audio.audio")
local C = require "mvtk.core.constants"

local M = {}
-- Per-encounter player responses, keyed by the manager id and its hash. Damage
-- messages carry only that id, keeping Defold's message buffer small.
local boss_profiles = {}
local feedback_targets = {}

local DEFAULTS = {
    melee = { shake = 6, hitstop = 0.02, rumble = 0.20, screen_shake = "light" },
    projectile = { shake = 4, hitstop = 0.015, rumble = 0.16, screen_shake = "light" },
    damage_over_time = { shake=0, hitstop=0, rumble=0, screen_shake=false },
    hurt = { shake = 5, hitstop = 0.02, rumble = 0.18, screen_shake = "medium" },
    parry = { shake = 7, hitstop = 0.03, rumble = 0.24, screen_shake = "medium" },
    perfect_parry = { shake = 9, hitstop = 0.05, rumble = 0.30, screen_shake = "heavy" },
}

-- Boss, telegraph and arena shake intensity. Named presets come from arena
-- effects; numbers come from boss phase and telegraph code. The camera reads
-- Gamefeel, so this converts an intensity into Gamefeel's pixel magnitude.
local SHAKE_DEFAULTS = {
    pixels_per_intensity = 8, duration = 0.3, max_intensity = 2.2,
    presets = { light = 0.5, medium = 1.0, heavy = 1.5, critical = 2.2 },
}

local function shake_settings()
    local config = CombatConfig.get()
    local configured = config and config.feedback and config.feedback.screen_shake
    local out = Util.deep_copy(SHAKE_DEFAULTS)
    if type(configured) == "table" then Util.deep_merge(out, configured) end
    return out
end

local function shake_intensity(settings, intensity)
    if type(intensity) == "string" and intensity ~= "" then
        return tonumber(settings.presets[intensity]) or tonumber(settings.presets.medium) or 1
    end
    -- boss_types.lua phase shakes say 5 to 20: without the cap that is a
    -- 40-160 pixel camera shake for seconds.
    local numeric = tonumber(intensity)
    if numeric then return math.min(tonumber(settings.max_intensity) or math.huge, math.max(0, numeric)) end
    return tonumber(settings.presets.medium) or 1
end

local function resolve(kind, overrides)
    local base = Util.deep_copy(DEFAULTS[kind or "melee"] or DEFAULTS.melee)
    local config = CombatConfig.get()
    local configured = config and config.feedback and config.feedback[kind or "melee"] or nil
    if type(configured) == "table" then
        Util.deep_merge(base, configured)
    end
    if type(overrides) == "table" then
        Util.deep_merge(base, overrides)
    end
    return base
end

function M.impact(kind, amount, overrides)
    local cfg = resolve(kind, overrides)
    if Gamefeel and Gamefeel.impact then
        pcall(Gamefeel.impact, amount or 0, {
            kind = (kind == "perfect_parry") and "parry" or kind,
            shake = cfg.shake,
            hitstop = cfg.hitstop,
            rumble = cfg.rumble,
            rumble_ms = cfg.rumble_ms,
            shake_dur = cfg.shake_dur,
        })
    end
    if Audio and cfg.sfx then
        pcall(Audio.sfx, cfg.sfx)
    end
end

-- Expose the same resolved settings to actor-specific recovery/visual handling.
function M.profile(kind, overrides)
    return resolve(kind, overrides)
end

function M.register_boss(id, player_profile)
    boss_profiles[id] = player_profile
    boss_profiles[hash(id)] = player_profile
end

function M.remove_boss(id)
    boss_profiles[id], boss_profiles[hash(id)] = nil, nil
end

function M.clear_bosses()
    boss_profiles = {}
end

function M.player_profile(payload)
    if payload and payload.damage_over_time then return resolve("damage_over_time"), false end
    local overrides = payload and boss_profiles[payload.boss_id]
    return resolve("hurt", overrides), overrides ~= nil
end

-- Bosses and weak points confirm their own damage before producing feedback.
-- Generic attack effects must not bypass their authored zero/none settings.
function M.set_target_owner(id, enabled)
    feedback_targets[id] = enabled and true or nil
end

-- Hitbox and projectile boss_id is a text property, "" for ordinary attacks.
-- Since T1.3 made it text, "" never equalled hash(""), so every player hit
-- skipped its hitstop, shake, rumble and sound (Stage 9, F4a step 58).
local function from_boss(id)
    return id ~= nil and id ~= "" and id ~= hash("")
end

function M.attack_impact(kind, amount, source_boss_id, target, overrides)
    if from_boss(source_boss_id) then return end
    if feedback_targets[target] then return end
    M.impact(kind, amount, overrides)
end

function M.play_sfx(sound_id)
    if Audio and sound_id then
        pcall(Audio.sfx, sound_id)
    end
end

function M.screen_shake(duration, intensity)
    if not (Gamefeel and Gamefeel.shake) then return end
    local settings = shake_settings()
    local magnitude = shake_intensity(settings, intensity) * (tonumber(settings.pixels_per_intensity) or 0)
    local seconds = tonumber(duration) or tonumber(settings.duration) or 0
    if magnitude > 0 and seconds > 0 then
        pcall(Gamefeel.shake, magnitude, seconds)
    end
end

-- fade.gui_script owns the full-screen flash. color.w is the peak alpha.
function M.flash(opts)
    opts = opts or {}
    local target = C.url("FADE_GUI") or "main:/ui#fade"
    pcall(msg.post, target, C.MSG.FLASH_SCREEN, {
        color = opts.color or vmath.vector4(1, 1, 1, 0.5),
        duration = tonumber(opts.duration) or 0.15,
    })
end

return M
