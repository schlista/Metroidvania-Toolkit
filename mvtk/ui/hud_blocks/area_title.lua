-- Region and landmark title card (mvtk/ui/region_titles.lua posts source text).
-- One authored text node, centred in the card: the title, then the subtitle on a
-- second line. The block owns the timing in update through its own clock: it
-- waits for the delay, holds (hidden, not advancing) while the game is frozen
-- (pause, dialogue, cutscenes, menus) or a boss arena is locked, and fades in
-- and out with gui.set_color. The showing card finishes; a newer card replaces
-- only the pending one, so just the newest waiting card is kept.
-- Before first visibility, a card left behind in another room/region is dropped.
-- A card still showing when the player dies ends there (on_data { clear = true }).
local GeneratedText = require "mvtk.ui.generated_text"
local MenuText = require "mvtk.ui.menu_text"
local RegionTitles = require "mvtk.ui.region_titles"
local DisplayText = require "mvtk.ui.display_text"
local Pause = require "mvtk.core.pause"
local Notices = require "mvtk.ui.notices"
local M = { id = "area_title", layout_key = "area_title", root = "area_title_root", field = "hud_area_title",
    size = { w = 440, h = 64 }, nodes = { static = 2, runtime_max = 0 }, text_role = "hud",
    default_entry = { enabled = true, visible = true, anchor = "top_center", offset = { x = 0, y = -300 },
        max_width = 440, mode = "first_visit", duration = 3, delay = 0.5, fade_in = 0.4, fade_out = 0.6 } }

local function arena_locked()
    local ok, locked = pcall(function() return require("mvtk.bosses.boss_arena").is_locked() end)
    return ok and locked == true
end
M._arena_locked = arena_locked

local function fit(state, source)
    local node = state.text
    local full = MenuText.render(source, DisplayText)
    local scale = gui.get_scale(node)
    local count = 0; for _ in full:gmatch("[^\128-\191]") do count = count + 1 end
    local text = full
    while text ~= "" do
        local size = GeneratedText.metrics(gui.get_font_resource(gui.get_font(node)), text, {
            width = state.width / scale.x, line_break = true,
            leading = gui.get_leading(node), tracking = gui.get_tracking(node) }, resource)
        if size.width * scale.x <= state.width and size.height * scale.y <= M.size.h then break end
        count = count - 1; text = Notices.trim(full, count)
    end
    state.set_text(node, text, true)
end

local function source_of(card)
    local subtitle = card.subtitle
    if type(subtitle) ~= "string" or subtitle == "" then return card.title end
    return { parts = { card.title, subtitle }, separator = "\n" }
end

local function alpha_of(state)
    local card, t = state.current, state.clock
    local fade_in, fade_out = math.max(0, card.fade_in), math.max(0, card.fade_out)
    if t < fade_in then return t / fade_in end
    local hold_end = fade_in + card.seconds
    if t <= hold_end then return 1 end
    if fade_out <= 0 then return 0 end
    return math.max(0, 1 - (t - hold_end) / fade_out)
end

local function set_alpha(state, alpha)
    if state.alpha == alpha then return end
    local color = gui.get_color(state.text)
    color.w = alpha
    gui.set_color(state.text, color)
    state.alpha = alpha
end

local function begin(state, card)
    state.current, state.clock, state.wait = card, 0, card.delay
    state.started = false
    state.revision = nil
end

local function finish(state)
    state.current, state.visible = nil, false
    if state.pending then
        local pending = state.pending
        state.pending = nil
        begin(state, pending)
    end
end

function M.init(state, get_node)
    state.text = get_node("area_title_text")
    state.visible = false
    local scale = state.hud_scale or 1
    local entry = state.layout or M.default_entry
    state.width = math.min(M.size.w * scale, entry.max_width or M.size.w) / scale
    local size, text_scale = gui.get_size(state.text), gui.get_scale(state.text)
    gui.set_size(state.text, vmath.vector3(state.width / text_scale.x, size.y, size.z))
    local position = gui.get_position(state.text)
    position.x = state.width / 2
    gui.set_position(state.text, position)
    gui.set_line_break(state.text, true)
end

function M.measure(state) return { w = state.width or M.size.w, h = M.size.h } end

function M.on_data(state, data)
    if type(data) == "table" and data.clear then
        -- region_titles posts this when the player dies: the showing card and any
        -- waiting one end, so neither finishes over the respawn room.
        state.current, state.pending, state.visible = nil, nil, false
        return
    end
    if type(data) ~= "table" or type(data.title) ~= "string" or data.title == "" then return end
    local entry = state.layout or M.default_entry
    local card = { title = data.title, subtitle = data.subtitle, kind = data.kind or "region",
        room_id = data.room_id, region_id = data.region_id,
        seconds = math.max(0, tonumber(data.seconds) or entry.duration or 3),
        delay = math.max(0, tonumber(data.delay) or entry.delay or 0.5),
        fade_in = tonumber(entry.fade_in) or 0.4, fade_out = tonumber(entry.fade_out) or 0.6 }
    if state.current then state.pending = card else begin(state, card) end
end

function M.update(state, dt, frozen)
    if not state.current then state.visible = false; return end
    if frozen or arena_locked() then state.visible = false; return end
    dt = math.max(0, dt or 0) * Pause.dt_scale()
    if state.wait > 0 then
        state.wait = state.wait - dt
        state.visible = false
        if state.wait > 0 then return end
        dt = -state.wait; state.wait = 0
    end
    local card = state.current
    if not state.started and not RegionTitles.is_current(card) then
        finish(state)
        return
    end
    state.clock = state.clock + dt
    if state.clock >= card.fade_in + card.seconds + math.max(0, card.fade_out) then
        finish(state)
        return
    end
    state.started = true
    state.visible = true
    if state.revision ~= DisplayText.revision() then
        fit(state, source_of(card))
        state.revision = DisplayText.revision()
    end
    set_alpha(state, alpha_of(state))
end

return M
