-- Engine boundary for GUI layout and raw pointer coordinates. The pure geometry
-- module is also used by the renderer; do not derive another fit policy here.
local Letterbox = require "mvtk.render.letterbox"
local ViewPolicy = require "mvtk.render.view_policy"
local Config = require "developer.config.game_config"
local Logger = require "mvtk.core.logger"
Logger.configure_from_debug_config()
local Log = Logger.get_logger("gameplay.camera")
local M = {}
local cached, previous_w, previous_h, previous_dw, previous_dh
local cached_frame, frame_rect, policy_revision
local revision = 0

function M.design_size()
    -- The validator requires these defaults to match game.project. Explicit
    -- project values remain authoritative; defaults also support headless tools.
    return sys.get_config_int("display.width", Config.window.target_width),
        sys.get_config_int("display.height", Config.window.target_height)
end

function M.rect()
    if not window or type(window.get_size) ~= "function" then return nil end
    local w, h = window.get_size()
    local dw, dh = M.design_size()
    if w ~= previous_w or h ~= previous_h or dw ~= previous_dw or dh ~= previous_dh then
        cached = Letterbox.rect(w, h, dw, dh)
        previous_w, previous_h, previous_dw, previous_dh = w, h, dw, dh
        if cached then
            Log.debug("letterbox gui window=%dx%d design=%dx%d rect=%d,%d,%d,%d scale=%.9f",
                w, h, dw, dh, cached.x, cached.y, cached.w, cached.h, cached.scale)
        else
            Log.debug("letterbox gui inactive window=%s,%s", tostring(w), tostring(h))
        end
    end
    return cached
end

function M.frame()
    local rect = M.rect()
    if not rect then return nil end
    local policy = ViewPolicy.current()
    local current_revision = ViewPolicy.revision()
    if rect ~= frame_rect or current_revision ~= policy_revision then
        cached_frame = Letterbox.frame(rect.window_w, rect.window_h, rect.design_w, rect.design_h, policy)
        frame_rect, policy_revision = rect, current_revision
        revision = revision + 1
    end
    return cached_frame
end

function M.picture()
    local frame = M.frame()
    return frame and frame.picture
end

function M.design_bounds(kind)
    local frame = M.frame()
    if not frame then return nil end
    if kind == "safe" then
        return { min_x = 0, min_y = 0, max_x = frame.design_w, max_y = frame.design_h }
    end
    local picture, fit = frame.picture, frame.gui
    return {
        min_x = (picture.x - fit.x) / frame.gui_scale,
        min_y = (picture.y - fit.y) / frame.gui_scale,
        max_x = (picture.x + picture.w - fit.x) / frame.gui_scale,
        max_y = (picture.y + picture.h - fit.y) / frame.gui_scale,
    }
end

function M.hud_rect(kind)
    local frame = M.frame()
    if not frame then return nil end
    local rect = kind == "picture" and frame.picture or frame.gui
    return { x = rect.x, y = rect.y, w = rect.w, h = rect.h, scale = frame.gui_scale,
        design_w = kind == "picture" and rect.w / frame.gui_scale or frame.design_w,
        design_h = kind == "picture" and rect.h / frame.gui_scale or frame.design_h }
end

function M.cover(node)
    local bounds = M.design_bounds("picture")
    if not bounds or not node then return end
    local w, h = M.design_size()
    local z = gui.get_position(node).z
    gui.set_pivot(node, gui.PIVOT_CENTER)
    gui.set_size(node, vmath.vector3(bounds.max_x - bounds.min_x, bounds.max_y - bounds.min_y, 0))
    gui.set_position(node, vmath.vector3(w / 2, h / 2, z))
end

function M.revision()
    if not M.frame() then return nil end
    return revision
end

function M.to_screen(dx, dy, rect)
    return Letterbox.design_to_screen(dx, dy, rect or M.rect())
end

function M.to_design(px, py, rect)
    return Letterbox.screen_to_design(px, py, rect or M.rect())
end

function M.pointer(action, rect)
    if not action or action.screen_x == nil or action.screen_y == nil then return nil, nil, false end
    rect = rect or M.rect()
    if not rect then return nil, nil, false end
    local x, y = Letterbox.screen_to_design(action.screen_x, action.screen_y, rect)
    -- Do not clamp: an already active drag must continue and release in a bar.
    local inside = action.screen_x >= rect.x and action.screen_y >= rect.y
        and action.screen_x < rect.x + rect.w and action.screen_y < rect.y + rect.h
    return x, y, inside
end

return M
