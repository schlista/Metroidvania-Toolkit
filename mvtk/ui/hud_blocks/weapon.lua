-- GUI boundary owns translation, measured one-line fitting and checked icons.
local GeneratedText = require "mvtk.ui.generated_text"
local AnimIndex = require "mvtk.core.anim_index"
local DisplayText = require "mvtk.ui.display_text"
local MenuText = require "mvtk.ui.menu_text"
local Notices = require "mvtk.ui.notices"
local M = {id="weapon", layout_key="weapon", root="weapon_root", field="hud_weapon",
    size={w=200,h=24}, nodes={static=3,runtime_max=0}, text_role="hud",
    default_entry={enabled=true,visible=true,anchor="top_right",offset={x=16,y=-108},max_width=356}}
local function fit(state, source)
    local text, count = source, 0
    for _ in source:gmatch("[^\128-\191]") do count = count + 1 end
    while text ~= "" do
        local metrics = GeneratedText.metrics(gui.get_font_resource(gui.get_font(state.label)), text, {
            line_break=false, leading=gui.get_leading(state.label), tracking=gui.get_tracking(state.label),
        }, resource)
        if metrics.width * state.label_scale.x <= math.max(0,state.width-28)
            and metrics.height * state.label_scale.y <= M.size.h then return text end
        count = count - 1
        text = Notices.trim(source,count)
    end
    return ""
end
local function render(state)
    -- The host's ordinary setter accepts strings, while menu descriptions need
    -- resolving here. Keep the original source for every language revision.
    local text = MenuText.render(state.data.name or "",DisplayText):gsub("[\r\n]"," ")
    state.set_text(state.label,fit(state,text),true)
    state.revision = DisplayText.revision()
end
function M.init(state, get_node)
    state.label, state.icon = get_node("weapon_label"), get_node("weapon_icon")
    state.label_scale = gui.get_scale(state.label)
    state.visible = false
    local scale = state.hud_scale or 1
    local maximum = (state.layout or M.default_entry).max_width or M.default_entry.max_width
    state.width = math.min(M.size.w * scale, maximum) / scale
    local size = gui.get_size(state.label)
    gui.set_size(state.label, vmath.vector3(math.max(0,state.width-28)/state.label_scale.x,size.y,size.z))
end
function M.on_data(state, data)
    state.data, state.visible = data, data.name ~= nil
    render(state)
    local icon = data.icon or {}
    local shown = state.visible and icon.texture == "gameplay_visuals"
        and AnimIndex.has("/developer/assets/atlas/gameplay_visuals.atlas", icon.anim) == true
    gui.set_enabled(state.icon, shown)
    if shown then gui.set_texture(state.icon, icon.texture); gui.play_flipbook(state.icon, icon.anim) end
end
function M.measure(state) return {w=state.width or M.size.w,h=M.size.h} end
function M.update(state)
    if state.data and state.revision ~= DisplayText.revision() then render(state) end
end
return M
