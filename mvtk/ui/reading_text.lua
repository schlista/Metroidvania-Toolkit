-- Shared reading typography. Geometry stays in design units; metrics are unscaled.
local Settings = require "mvtk.core.settings"
local GeneratedText = require "mvtk.ui.generated_text"
local Accessibility = require "mvtk.ui.accessibility"
local M = {}

function M.scale()
    return Accessibility.text_scale(Settings.get_accessibility(), "reading")
end

function M.revision() return Settings.accessibility_revision() end

function M.resize(gui_api, node, base, scale, width, height)
    gui_api.set_scale(node, vmath.vector3(base.x * scale, base.y * scale, base.z))
    gui_api.set_line_break(node, true)
    gui_api.set_size(node, vmath.vector3(width / (base.x * scale), height / (base.y * scale), 0))
end

function M.metrics(gui_api, resources, node, text, width)
    local scale = gui_api.get_scale(node)
    local metrics = GeneratedText.metrics(gui_api.get_font_resource(gui_api.get_font(node)), text,
        { width = width / scale.x, line_break = true,
            leading = gui_api.get_leading(node), tracking = gui_api.get_tracking(node) }, resources)
    return metrics.width * scale.x, metrics.height * scale.y
end

-- Split only at UTF-8 boundaries, preferring word boundaries. Keep every byte:
-- translations, explicit newlines and input tokens have already been resolved.
function M.pages(text, fits, height, last_height)
    local pages, rest = {}, text
    while rest ~= "" and not fits(rest, height) do
        local ends = {}
        for at in rest:gmatch("()[^\128-\191]") do
            if at > 1 then ends[#ends + 1] = at - 1 end
        end
        ends[#ends + 1] = #rest
        local low, high, best = 1, #ends, 0
        while low <= high do
            local mid = math.floor((low + high) / 2)
            if fits(rest:sub(1, ends[mid]), height) then best = ends[mid]; low = mid + 1
            else high = mid - 1 end
        end
        -- A single glyph must fit the configured panel/font. Never loop forever.
        assert(best > 0, "Dialogue panel cannot fit one reading glyph")
        local boundary = rest:sub(1, best):match(".*()%s")
        if boundary and boundary > 1 then best = boundary end
        pages[#pages + 1], rest = rest:sub(1, best), rest:sub(best + 1)
    end
    pages[#pages + 1] = rest
    if last_height and not fits(rest, last_height) then
        -- Keep the text on the preceding page when choices need the final page.
        pages[#pages + 1] = ""
    end
    return pages
end

return M
