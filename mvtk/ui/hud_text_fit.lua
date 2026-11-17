-- Fit an already rendered HUD label into its authored local text bounds.
-- Keep glyph scale fixed: long translations lose trailing codepoints, not size.
local GeneratedText = require "mvtk.ui.generated_text"
local Notices = require "mvtk.ui.notices"
local M = {}

local function fits(gui_api, resources, node, text, bounds)
    local metrics = GeneratedText.metrics(gui_api.get_font_resource(gui_api.get_font(node)), text, {
        line_break = false, leading = gui_api.get_leading(node), tracking = gui_api.get_tracking(node) }, resources)
    return metrics.width <= bounds.x and metrics.height <= bounds.y
end

function M.line(gui_api, resources, node, source)
    local text = source:gsub("[\r\n]", " ")
    local original, count = text, 0
    for _ in text:gmatch("[^\128-\191]") do count = count + 1 end
    local bounds = gui_api.get_size(node)
    while text ~= "" do
        if fits(gui_api, resources, node, text, bounds) then return text end
        count = count - 1
        text = Notices.trim(original, count)
    end
    return ""
end

-- Shorten only a name, retaining its button, selection marker and count.
function M.decorated(gui_api, resources, node, name, format)
    local bounds, count = gui_api.get_size(node), 0
    for _ in name:gmatch("[^\128-\191]") do count = count + 1 end
    while count >= 0 do
        local text = format(Notices.trim(name, count)):gsub("[\r\n]", " ")
        if fits(gui_api, resources, node, text, bounds) then return text end
        count = count - 1
    end
    return M.line(gui_api, resources, node, format(""))
end

return M
