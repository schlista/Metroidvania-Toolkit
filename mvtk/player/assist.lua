-- Player assist owns damage, persistent speed and kill-contact rescue policies.
-- Preferences remain live; creator config is copied only when its revision changes.
local Settings = require "mvtk.core.settings"
local Config = require "developer.config.accessibility"
local RuntimeSettings = require "developer.config.runtime_settings"
local Pause = require "mvtk.core.pause"
local HazardContact = require "mvtk.hazards.hazard_contact"
local M = {}
local cached, cached_revision
local session_running = false
local session_used, session_slowed = false, false
local slow_marks, applied_slowed = 0, false

local function config()
    local revision = RuntimeSettings.revision()
    if not cached or cached_revision ~= revision then
        cached = RuntimeSettings.section("accessibility", Config).assist
        cached_revision = revision
    end
    return cached
end

local function snapped(key, cfg)
    local value = tonumber(Settings.get("accessibility.assist." .. key)) or 1
    local nearest, distance = 1, math.huge
    for _, candidate in ipairs(cfg[key]) do
        local delta = math.abs(candidate - value)
        if delta < distance then nearest, distance = candidate, delta end
    end
    return nearest
end

M.MULTIPLIER_SOURCE = {
    id = "assist", order = 40, challenge = true, range = { 0, 1 },
    factor = function(channel)
        local cfg = config()
        if channel ~= "damage_to_player" or not cfg.allowed then return 1 end
        return snapped("damage_taken", cfg)
    end,
}

function M.active()
    local cfg = config()
    return cfg.allowed and (snapped("damage_taken", cfg) < 1 or M.slowed()
        or Settings.get("accessibility.assist.pit_rescue") == true) or false
end
function M.slowed()
    local cfg = config()
    return cfg.allowed and snapped("game_speed", cfg) < 1 or false
end
function M.record_use() return config().record_use == true end
function M.blocks_achievements() return M.record_use() and config().block_achievements == true end
function M.run_marker() return {marks = slow_marks, slowed = M.slowed()} end
function M.was_slowed(marker)
    return marker.slowed or M.slowed() or slow_marks ~= marker.marks
end
local function write_marks()
    local Flags = require "mvtk.core.flags"
    local Events = require "mvtk.core.game_events"
    -- Flag events must see both marks, including ending speed achievements.
    local mark = Events.hold()
    local ok, err = pcall(function()
        if session_used and not Flags.has("assist_used") then Flags.set("assist_used", true) end
        if session_slowed and not Flags.has("assist_slowed") then Flags.set("assist_slowed", true) end
    end)
    if not ok then Events.discard(mark); error(err, 0) end
    Events.release(mark)
end
function M.note_use()
    if not session_running then return end
    session_used = session_used or (M.record_use() and M.active())
    session_slowed = session_slowed or M.slowed()
    write_marks()
end
-- Fresh sessions inherit only the loaded save; New Game+ carry has already run.
function M.begin_session()
    local Flags = require "mvtk.core.flags"
    session_used, session_slowed = Flags.has("assist_used"), Flags.has("assist_slowed")
    session_running = true
    M.note_use()
end
-- Death retains elapsed time and this session's historical marks, even after
-- preferences return to normal. Restore before death fees or other save effects.
function M.after_restart_load(load_ok)
    if load_ok and session_running then write_marks() end
end
function M.end_session()
    session_running, session_used, session_slowed = false, false, false
end

function M.apply()
    local cfg = config()
    local speed = snapped("game_speed", cfg)
    Pause.set_speed_factor("assist", cfg.allowed and speed or nil, true)
    local slowed = cfg.allowed and speed < 1 or false
    if slowed and not applied_slowed then slow_marks = slow_marks + 1 end
    applied_slowed = slowed
    M.note_use()
end

HazardContact.register_player_mode("assist", function(mode, lethal, damage)
    local cfg = config()
    if mode == "kill" and cfg.allowed and Settings.get("accessibility.assist.pit_rescue") == true then
        return "safe_return", cfg.pit_damage
    end
    return mode, damage
end)

return M
