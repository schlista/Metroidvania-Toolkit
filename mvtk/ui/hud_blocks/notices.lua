-- One authored panel, reused for each queued milestone. No runtime nodes.
local GeneratedText = require "mvtk.ui.generated_text"
local Reading = require "mvtk.ui.reading_text"
local Queue = require "mvtk.ui.notice_queue"
local Notices = require "mvtk.ui.notices"
local DisplayText = require "mvtk.ui.display_text"
local InputPrompts = require "mvtk.ui.input_prompts"
local AnimIndex = require "mvtk.core.anim_index"
local Audio = require "mvtk.audio.audio"
local Geometry = require "mvtk.ui.hud_block_layout"
local Config = require "developer.config.hud_layout"
local M = { id = "notices", layout_key = "notices", root = "notice_panel", field = "hud_notices",
    top_floor_key = "notices_top_floor", max_width_key = "notices_max_width",
    text_role = "reading", nodes = { static = 4, runtime_max = 0 }, size = { w = 400, h = 160 },
    default_entry = { enabled = true, visible = true, anchor = "top_right", offset = { x = 16, y = 0 },
        follow_minimap = true, top_floor = 106, max_width = Config.notices_max_width, width = 400, max_height = 160, duration = 2.5, max_queue = 6,
        fade_in = 0.15, fade_out = 0.25 } }
local TEXTURES = { gameplay_visuals = "/developer/assets/atlas/gameplay_visuals.atlas" }

local function metrics(node, source, width)
    local scale = gui.get_scale(node)
    local result = GeneratedText.metrics(gui.get_font_resource(gui.get_font(node)),
        source, { width = width / scale.x, line_break = true,
            leading = gui.get_leading(node), tracking = gui.get_tracking(node) }, resource)
    return result.height * scale.y, result.width * scale.x
end

local function fit(node, source, width, height)
    local text, count = source, 0
    -- Fit the rendered translation, trimming only at codepoint boundaries.
    for _ in source:gmatch("[^\128-\191]") do count = count + 1 end
    while text ~= "" do
        local h, w = metrics(node, text, width)
        if h <= height and w <= width then return text, h end
        count = count - 1
        text = Notices.trim(source, count)
    end
    return "", 0
end

local function layout(state, notice)
    local scale = Reading.scale()
    gui.set_scale(state.title, vmath.vector3(state.title_scale.x * scale, state.title_scale.y * scale, state.title_scale.z))
    gui.set_scale(state.body, vmath.vector3(state.body_scale.x * scale, state.body_scale.y * scale, state.body_scale.z))
    local cfg = state.layout
    local effective_scale = state.scale.x * state.hud_scale
    local width = Geometry.scaled_width(cfg.width, effective_scale, state.max_width or cfg.max_width) / effective_scale
    local maximum = cfg.max_height
    local title_pos, body_pos = state.title_position, state.body_position
    local body_width = math.max(1, width - body_pos.x - 12)
    local title_source, body_source = Notices.render(notice, DisplayText)
    local title, title_h = fit(state.title, title_source, math.max(1, width - title_pos.x - 12), 32)
    local body_y = math.max(-body_pos.y, -title_pos.y + title_h + 8)
    local text, body_h = fit(state.body, body_source, body_width, math.max(0, maximum - body_y - 12))
    local scale = gui.get_scale(state.body)
    gui.set_size(state.body, vmath.vector3(body_width / scale.x, body_h / scale.y, 0))
    gui.set_position(state.body, vmath.vector3(body_pos.x, -body_y, body_pos.z))
    local title_scale = gui.get_scale(state.title)
    gui.set_size(state.title, vmath.vector3((width - title_pos.x - 12) / title_scale.x, title_h / title_scale.y, 0))
    state.set_text(state.title, title, true)
    state.set_text(state.body, text, true)
    local height = math.min(maximum, math.max(64, body_y + body_h + 12))
    gui.set_size(state.panel, vmath.vector3(width, height, 0))
    state.size = { w = width * state.scale.x, h = height * state.scale.y }
end

function M.init(state, get_node)
    state.panel, state.title = get_node("notice_panel"), get_node("notice_title")
    state.body, state.icon = get_node("notice_body"), get_node("notice_icon")
    state.scale = gui.get_scale(state.panel)
    state.title_scale, state.body_scale = gui.get_scale(state.title), gui.get_scale(state.body)
    state.title_position, state.body_position = gui.get_position(state.title), gui.get_position(state.body)
    state.queue = Queue.new(state.layout)
    state.visible = false
    gui.set_line_break(state.body, true)
    gui.set_line_break(state.title, true)
    gui.set_enabled(state.title, true); gui.set_enabled(state.body, true)
end
function M.on_data(state, data)
    local notice = data.notice_ref and Notices.take(data.notice_ref) or data
    if notice then Queue.push(state.queue, notice) end
end
function M.update(state, dt, frozen)
    local notice, alpha = Queue.tick(state.queue, dt, frozen)
    state.visible = notice ~= nil and not frozen
    if not state.visible then return end
    local revision = DisplayText.revision()
    if state.current ~= notice or state.revision ~= revision or state.reading_revision ~= Reading.revision() then
        layout(state, notice)
        state.revision = revision
        state.reading_revision = Reading.revision()
    end
    if state.current ~= notice then
        local icon = notice.icon or {}
        local atlas = TEXTURES[icon.texture]
        local shown = atlas and AnimIndex.has(atlas, icon.anim) == true or false
        gui.set_enabled(state.icon, shown)
        if shown then gui.set_texture(state.icon, icon.texture); gui.play_flipbook(state.icon, icon.anim) end
        if notice.sound and notice.sound ~= "" then Audio.sfx(notice.sound) end
        state.current = notice
    end
    if state.alpha ~= alpha then gui.set_alpha(state.panel, alpha); state.alpha = alpha end
end
function M.measure(state) return state.size or M.size end
return M
