-- Shared, engine-free design-view geometry. Coordinates use a bottom-left origin.
local M = {}
local warned_integer_fallback = false

local function positive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function M.rect(window_w, window_h, design_w, design_h)
    if not positive(window_w) or not positive(window_h)
        or not positive(design_w) or not positive(design_h) then return nil end
    local scale = math.min(window_w / design_w, window_h / design_h)
    -- Round the fitted extent to the nearest pixel; put an odd spare pixel at
    -- the top/right. Conversions retain the same uniform (unrounded) scale.
    local w = math.floor(design_w * scale + 0.5)
    local h = math.floor(design_h * scale + 0.5)
    return {
        x = math.floor((window_w - w) / 2), y = math.floor((window_h - h) / 2),
        w = w, h = h, scale = scale,
        design_w = design_w, design_h = design_h,
        window_w = window_w, window_h = window_h,
    }
end

-- The GUI keeps the fitted design area while the world can grow around it.
function M.frame(window_w, window_h, design_w, design_h, policy)
    local rect = M.rect(window_w, window_h, design_w, design_h)
    if not rect then return nil end
    local scale = rect.scale
    if policy and policy.scale_rule == "integer" then
        local zoom = positive(policy.default_zoom) and policy.default_zoom or 1
        local k = math.floor(scale * zoom + 0.000001)
        if k >= 1 then
            scale = k / zoom
        elseif not warned_integer_fallback then
            print("[View] Window too small for whole pixels; using fit scaling.")
            warned_integer_fallback = true
        end
    end
    local picture = {}
    for key, value in pairs(rect) do picture[key] = value end
    if scale ~= rect.scale then
        picture.w = math.floor(design_w * scale + 0.5)
        picture.h = math.floor(design_h * scale + 0.5)
        picture.scale = scale
        picture.x = math.floor((window_w - picture.w) / 2)
        picture.y = math.floor((window_h - picture.h) / 2)
    end
    local view_w, view_h = design_w, design_h
    if policy and policy.mode == "expand" then
        local aspect = math.max(policy.min_aspect or 4 / 3,
            math.min(policy.max_aspect or 2.4, window_w / window_h))
        if aspect >= design_w / design_h then
            picture.w = math.min(window_w, math.floor(picture.h * aspect + 0.5))
        else
            picture.h = math.min(window_h, math.floor(picture.w / aspect + 0.5))
        end
        picture.x = math.floor((window_w - picture.w) / 2)
        picture.y = math.floor((window_h - picture.h) / 2)
        view_w, view_h = picture.w / scale, picture.h / scale
    end
    if policy and policy.scale_rule == "integer" then
        view_w, view_h = picture.w / scale, picture.h / scale
    end
    return {
        gui = rect, picture = picture, scale = scale, gui_scale = rect.scale,
        view_w = view_w, view_h = view_h,
        offset_x = picture.x, offset_y = picture.y,
        design_w = design_w, design_h = design_h,
        window_w = window_w, window_h = window_h,
    }
end

function M.screen_to_design(px, py, rect)
    if not rect or not positive(rect.scale) or px == nil or py == nil then return nil end
    return (px - rect.x) / rect.scale, (py - rect.y) / rect.scale
end

function M.design_to_screen(dx, dy, rect)
    if not rect or not positive(rect.scale) or dx == nil or dy == nil then return nil end
    return rect.x + dx * rect.scale, rect.y + dy * rect.scale
end

return M
