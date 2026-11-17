-- World-pickup temporary sources; the shared stats owner ticks and clears them.
-- Producers send creator source labels. The GUI alone translates and counts down.
local PlayerStats = require "mvtk.player.player_stats"
local RuntimeSettings = require "developer.config.runtime_settings"
local Baseline = require "developer.config.powerups"
local HudBus = require "mvtk.ui.hud_bus"
local M = {}
local cached, revision
local durations = {}
local function settings()
    local current = RuntimeSettings.revision()
    if cached == nil or current ~= revision then
        cached, revision = RuntimeSettings.section("powerups", Baseline), current
    end
    return cached
end
local function post_hud()
    local rows, live = {}, {}
    local cfg = settings()
    for _, source in ipairs(PlayerStats.describe()) do
        local id = source.id:match("^powerup:(.+)$")
        local entry = id and (cfg.powerups or {})[id]
        if entry and source.layer == "temporary" and source.remaining then
            live[source.id] = true
            rows[#rows + 1] = {id=id, label=entry.name, remaining=source.remaining,
                duration=durations[source.id] or entry.duration}
        end
    end
    for id in pairs(durations) do if not live[id] then durations[id] = nil end end
    HudBus.post("powerups", {rows=rows})
end
function M.apply(id)
    local cfg = settings()
    local entry = (cfg.powerups or {})[id]
    if not cfg.enabled or not entry then return false end
    local source = "powerup:" .. id
    local duration = entry.duration
    if cfg.stacking == "extend" then duration = duration + (PlayerStats.remaining(source) or 0) end
    if not PlayerStats.set_source(source, entry.effects, {layer="temporary", duration=duration}) then return false end
    durations[source] = duration
    -- Stats deliberately does not emit when only the duration was refreshed.
    post_hud()
    return true
end
PlayerStats.register_listener(function(reason, id)
    if reason == "reset" or ((reason == "expire" or reason == "clear")
        and type(id) == "string" and id:sub(1,8) == "powerup:") then post_hud() end
end)
function M.on_session_start() post_hud() end
return M
