-- Shared across boot and the streamed game proxy. Only boot drives the fade
-- clock, so a paused game or an unloaded session cannot strand the cover.
local RuntimeSettings = require "developer.config.runtime_settings"
local M = {}
local phase, opacity = "idle", 0
local placed, camera, decision, opening
local color, duration
-- A load that never reports ready must not leave the screen black for good.
local DEFAULT_MAX_WAIT = 12
local max_wait, waited = DEFAULT_MAX_WAIT, 0

function M.begin()
    local cfg = RuntimeSettings.section("display", require "developer.config.display_settings").startup
    if not cfg then
        -- Legacy display files predate this section. RuntimeSettings already
        -- loads this model; reuse its developer-authored defaults, rather than
        -- copying presentation values into framework code.
        local fields = require("mvtk.core.creator_settings_model").fields
        cfg = { color = { r = fields.startup_cover_red.default,
            g = fields.startup_cover_green.default, b = fields.startup_cover_blue.default },
            fade_out_seconds = fields.startup_cover_fade.default }
    end
    color, duration = cfg.color, cfg.fade_out_seconds
    max_wait, waited = tonumber(cfg.max_wait_seconds) or DEFAULT_MAX_WAIT, 0
    phase, opacity = "loading", 1
    placed, camera, decision, opening = false, false, false, nil
end
function M.cancel() phase, opacity, opening = "idle", 0, nil end
function M.active() return phase ~= "idle" end
function M.alpha() return opacity end
function M.color() return color end
function M.player_placed() if phase == "loading" then placed = true end end
function M.needs_snap() return phase == "loading" and placed and not camera end
function M.camera_ready() if placed then camera = true end end
function M.ready() return placed and camera end
function M.decide(id) decision, opening = true, id or nil end
function M.claim_opening(id) return phase == "loading" and opening == id end
function M.opening_failed(id) if opening == id then opening = nil end end
-- Called by the fade GUI only after its opaque node has been installed.
function M.handoff() if opening then M.cancel() end end
function M.tick(dt)
    if phase == "loading" then
        waited = waited + math.max(0, dt or 0)
        if waited >= max_wait then
            print(string.format("[STARTUP_COVER] still covered after %.1f s (player placed=%s, camera ready=%s, "
                .. "opening decided=%s, opening pending=%s); revealing anyway", waited, tostring(placed),
                tostring(camera), tostring(decision), tostring(opening)))
            opening, phase = nil, "revealing"
        end
    end
    if phase == "loading" and placed and camera and decision and not opening then phase = "revealing" end
    if phase == "revealing" then
        opacity = duration == 0 and 0 or math.max(0, opacity - math.max(0, dt) / duration)
        if opacity == 0 then phase = "idle" end
    end
end
return M
