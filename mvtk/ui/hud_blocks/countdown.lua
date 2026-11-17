-- Countdown events (WM09): the running countdown's label and clock, then its
-- result for a few seconds. countdown.lua posts only when the shown value
-- changes (whole seconds, or tenths below tenths_below) and sends tenths and
-- source text; only this GUI-owned block formats them, through TimeText.
local GeneratedText = require "mvtk.ui.generated_text"
local DisplayText = require "mvtk.ui.display_text"
local MenuText = require "mvtk.ui.menu_text"
local Notices = require "mvtk.ui.notices"
local TimeText = require "mvtk.ui.time_text"
local Pause = require "mvtk.core.pause"
local M = {id="countdown", layout_key="countdown", root="countdown_root", field="hud_countdown",
    size={w=240,h=56}, nodes={static=3,runtime_max=0}, text_role="hud",
    -- WM09-D6 (a): bottom centre, above the toast band; never in the top-right column.
    default_entry={enabled=true,visible=true,anchor="bottom_center",offset={x=0,y=180},max_width=356}}
M.LINE = {label=22, clock=33}

-- Longest prefix of a rendered description that fits one line of the block.
local function fit(state, node, source, height)
    local text = MenuText.render(source, DisplayText):gsub("[\r\n]", " ")
    local original, count = text, 0
    for _ in text:gmatch("[^\128-\191]") do count = count + 1 end
    local scale = gui.get_scale(node)
    while text ~= "" do
        local metrics = GeneratedText.metrics(gui.get_font_resource(gui.get_font(node)), text, {
            line_break=false, leading=gui.get_leading(node), tracking=gui.get_tracking(node)}, resource)
        if metrics.width * scale.x <= state.width and metrics.height * scale.y <= height then break end
        count = count - 1
        text = Notices.trim(original, count)
    end
    -- Already rendered here; the host must not translate it a second time.
    state.set_text(node, text, true)
end

-- Shown clock: m:ss while whole seconds show, m:ss.t once tenths do.
function M.clock_text(remaining, tenths)
    remaining = math.max(0, math.floor(tonumber(remaining) or 0))
    if tenths then return TimeText.playtime(math.floor(remaining / 10), remaining % 10) end
    return TimeText.clock(math.floor((remaining + 9) / 10))
end

local function color(entry_color, fallback)
    if type(entry_color) ~= "table" then return fallback end
    return vmath.vector4(tonumber(entry_color.r) or 1, tonumber(entry_color.g) or 1,
        tonumber(entry_color.b) or 1, tonumber(entry_color.a) or 1)
end

local function render(state)
    local data = state.data
    if not data or not state.visible then return end
    local label, clock, warning
    if data.state == "result" then
        label = data.title or {text=data.label or ""}
        clock = data.text
        if data.tenths ~= nil and not clock then
            clock = {key=data.new_best and "countdown.result_best" or "countdown.result",
                params={time=M.clock_text(data.tenths, true)}}
        end
    else
        label = {text=data.label or ""}
        clock = M.clock_text(data.remaining, data.tenths_shown == true)
        warning = data.warning == true
    end
    fit(state, state.label, label or "", M.LINE.label)
    fit(state, state.clock, clock or "", M.LINE.clock)
    gui.set_color(state.clock, warning and state.warning_color or state.normal_color)
    state.revision = DisplayText.revision()
end

function M.init(state, get_node)
    state.label, state.clock = get_node("countdown_label"), get_node("countdown_clock")
    state.visible = false
    local entry = state.layout or M.default_entry
    local scale = state.hud_scale or 1
    state.width = math.min(M.size.w * scale, entry.max_width or M.default_entry.max_width) / scale
    for _, node in ipairs({state.label, state.clock}) do
        local size, text_scale = gui.get_size(node), gui.get_scale(node)
        gui.set_size(node, vmath.vector3(state.width / text_scale.x, size.y, size.z))
        local position = gui.get_position(node)
        position.x = state.width / 2
        gui.set_position(node, position)
    end
    state.normal_color = gui.get_color(state.clock)
    state.warning_color = color(entry.warning_color, state.normal_color)
end

function M.measure(state) return {w=state.width or M.size.w, h=M.size.h} end

-- {state="running"|"result"|"idle"}; idle hides the block.
function M.on_data(state, data)
    state.data = data
    state.visible = data.state == "running" or data.state == "result"
    state.remaining = data.state == "result" and (tonumber(data.duration) or 0) or nil
    render(state)
end

-- Only the result's display time is ticked here, through this block's own
-- clock; pause, dialogue and cutscenes hold it as they hold the countdown.
function M.update(state, dt, frozen)
    if not state.visible then return end
    if state.remaining and not frozen then
        state.remaining = math.max(0, state.remaining - math.max(0, dt or 0) * Pause.dt_scale())
        if state.remaining == 0 then state.visible = false; return end
    end
    if state.revision ~= DisplayText.revision() then render(state) end
end
return M
