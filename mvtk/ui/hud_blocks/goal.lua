-- The current goal's title on one measured line. goals.lua sends source text;
-- only this GUI-owned block resolves it, again after each language change.
local GeneratedText = require "mvtk.ui.generated_text"
local DisplayText = require "mvtk.ui.display_text"
local MenuText = require "mvtk.ui.menu_text"
local Notices = require "mvtk.ui.notices"
local Config = require "developer.config.hud_layout"
local M = {id="goal", layout_key="goal", root="goal_root", field="hud_goal",
    size=Config.goal.size, nodes={static=1,runtime_max=0}, text_role="hud",
    default_entry=Config.goal}
-- Longest prefix that fits the block's width on one line.
local function fit(state, source)
    local text, count = source, 0
    for _ in source:gmatch("[^\128-\191]") do count = count + 1 end
    while text ~= "" do
        local metrics = GeneratedText.metrics(gui.get_font_resource(gui.get_font(state.label)), text, {
            line_break=false, leading=gui.get_leading(state.label), tracking=gui.get_tracking(state.label),
        }, resource)
        if metrics.width * state.label_scale.x <= state.width
            and metrics.height * state.label_scale.y <= M.size.h then return text end
        count = count - 1
        text = Notices.trim(source, count)
    end
    return ""
end
local function render(state)
    local text = MenuText.render(state.data.title or "", DisplayText):gsub("[\r\n]", " ")
    -- Already rendered here; the host must not translate it a second time.
    state.set_text(state.label, fit(state, text), true)
    state.revision = DisplayText.revision()
end
function M.init(state, get_node)
    state.label = get_node(M.root)
    state.label_scale = gui.get_scale(state.label)
    state.visible = false
    local scale = state.hud_scale or 1
    local maximum = (state.layout or M.default_entry).max_width or M.default_entry.max_width
    state.width = math.min(M.size.w * scale, maximum) / scale
    local size = gui.get_size(state.label)
    gui.set_size(state.label, vmath.vector3(state.width / state.label_scale.x, size.y, size.z))
end
function M.on_data(state, data)
    local title = data.title
    state.data = data
    state.visible = type(title) == "string" and title:find("%S") ~= nil
    render(state)
end
function M.measure(state) return {w=state.width or M.size.w, h=M.size.h} end
function M.update(state)
    if state.data and state.revision ~= DisplayText.revision() then render(state) end
end
return M
