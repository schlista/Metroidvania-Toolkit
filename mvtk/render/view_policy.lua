-- Picture policy is pure to resolve; runtime settings are loaded only on demand.
local Letterbox = require "mvtk.render.letterbox"
local M = {}
local cached, settings_revision
local revision = 0
local view_fill = "auto"
local scale_cache = {}

local function number_in(value, low, high, fallback)
    if type(value) == "number" and value == value and value < math.huge and value >= low and value <= high then return value end
    return fallback
end

function M.resolve(display_cfg, default_zoom)
    local cfg = type(display_cfg) == "table" and display_cfg or {}
    local view = type(cfg.view) == "table" and cfg.view or {}
    local color = type(cfg.letterbox_color) == "table" and cfg.letterbox_color or {}
    return {
        mode = view.mode == "expand" and "expand" or "letterbox",
        player_choice = view.player_choice == true,
        min_aspect = number_in(view.min_aspect, 1, 16 / 9, 4 / 3),
        max_aspect = number_in(view.max_aspect, 16 / 9, 4, 2.4),
        scale_rule = view.scale_rule == "integer" and "integer" or "fit",
        hud_frame = view.hud_frame == "picture" and "picture" or "safe",
        mask_outside_room = view.mask_outside_room ~= false,
        letterbox_color = {
            r = number_in(color.r, 0, 1, 0), g = number_in(color.g, 0, 1, 0), b = number_in(color.b, 0, 1, 0),
        },
        default_zoom = number_in(default_zoom, 0.000001, math.huge, 1),
    }
end

function M.current()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local current_revision = RuntimeSettings.revision()
    if not cached or settings_revision ~= current_revision then
        cached = M.resolve(RuntimeSettings.section("display", require "developer.config.display_settings"),
            RuntimeSettings.get_camera_config().default_zoom)
        if cached.player_choice and (view_fill == "expand" or view_fill == "letterbox") then
            cached.mode = view_fill
        end
        settings_revision = current_revision
        revision = revision + 1
    end
    return cached
end

function M.invalidate()
    cached = nil
    revision = revision + 1
end

-- Preferences and the renderer share this module cache with game scripts.
function M.set_view_fill(value)
    view_fill = (value == "expand" or value == "letterbox") and value or "auto"
    M.invalidate()
end

function M.revision() return revision end

function M.frame(w, h, policy)
    if not window or type(window.get_size) ~= "function" then return nil end
    if w == nil then w, h = window.get_size() end
    if not sys or type(sys.get_config_int) ~= "function" then return nil end
    return Letterbox.frame(w, h, sys.get_config_int("display.width"), sys.get_config_int("display.height"), policy or M.current())
end

local function scales()
    -- Headless tools must not pull in runtime preferences or engine configuration.
    if not window or type(window.get_size) ~= "function" then return nil end
    local w, h = window.get_size()
    local policy = M.current()
    local current_revision = M.revision()
    if scale_cache.w ~= w or scale_cache.h ~= h or scale_cache.revision ~= current_revision then
        local frame = M.frame(w, h, policy)
        scale_cache = { w = w, h = h, revision = current_revision,
            x = frame and frame.view_w / frame.design_w or 1,
            y = frame and frame.view_h / frame.design_h or 1,
            world = frame and frame.scale or 1 }
    end
    return scale_cache
end

function M.view_scale()
    local scale = scales()
    return scale and scale.x or 1, scale and scale.y or 1
end

-- Physical pixels per design unit; shared with camera quantization. The picture
-- itself remains available through frame() for a future picture-sized target.
function M.world_scale()
    local scale = scales()
    return scale and scale.world or 1
end

return M
