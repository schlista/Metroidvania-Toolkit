local GeneratedText = require "mvtk.ui.generated_text"
-- World map stamps (G8-07): draws the player's stamps and the stamp palette,
-- and handles the palette's input. Saved state lives in mvtk/map/map_stamps.lua;
-- this module only creates and moves its own nodes.
--
-- Called from mvtk/ui/world_map_overlay.lua (drawing, with the overlay's ctx)
-- and developer/ui/menus/world_map.gui_script (input and legend):
--
--   Stamps.items(self, ctx)                  -- draws stamps; returns pointable items
--   Stamps.update(self, ctx, hit, x, y, room)-- remembers the cursor; draws the palette
--   Stamps.input(self, action_id, action)    -- true when the input was the palette's
--   Stamps.is_open(self), Stamps.legend(self), Stamps.palette_legend(self)
--   Stamps.hide(self)
--
-- Controls (map only, never in fast travel): X or the X key opens the palette
-- at the cursor; left and right choose a stamp, A places it and B cancels.
-- X with the cursor on a stamp removes it. Panning stops while the palette is
-- open. Text: icon glyphs and labels are creator source text; framework words
-- are ui_text keys. Both are resolved here, through DisplayText.
local MapStamps = require "mvtk.map.map_stamps"

local Typography = require "developer.config.menu_typography"
local M = {}

-- Display modules are looked up at call time, like the overlay's callers do,
-- so a test's stand-in is never captured for the whole session.
local DisplayText = setmetatable({}, { __index = function(_, k) return require("mvtk.ui.display_text")[k] end })
local InputPrompts = setmetatable({}, { __index = function(_, k) return require("mvtk.ui.input_prompts")[k] end })
local Viewport = setmetatable({}, { __index = function(_, k) return require("mvtk.ui.viewport")[k] end })

-- Raw input ids that open the palette or remove the stamp under the cursor.
M.INPUTS = { "gamepad_rpad_left", "key_x" }
-- Palette nodes (mvtk/map/map_view.lua POOLS "stamps" reserves 8): the
-- backdrop, the caption and up to six icons.
M.PALETTE_ICONS = 6
M.DEFAULT_COLOR = { 1, 1, 1, 1 }

local v3, v4 = vmath.vector3, vmath.vector4

local input_index
local function is_stamp_input(id)
    if id == nil then return false end
    if not input_index then
        input_index = {}
        for _, name in ipairs(M.INPUTS) do
            input_index[name] = true
            if hash then input_index[hash(name)] = true end
        end
    end
    return input_index[id] == true
end
M.is_input = is_stamp_input

local function state(self)
    local st = self._stamps
    if not st then
        st = { nodes = {}, palette = { icons = {} }, choice = 1 }
        self._stamps = st
    end
    return st
end

local function color_of(value)
    if type(value) == "userdata" then return value end
    if type(value) == "table" then
        return v4(value.x or value[1] or 1, value.y or value[2] or 1, value.z or value[3] or 1, value.w or value[4] or 1)
    end
    local d = M.DEFAULT_COLOR
    return v4(d[1], d[2], d[3], d[4])
end

local function text_node(parent, pivot)
    local node = GeneratedText.new(gui, "/developer/ui/menus/world_map.gui", v3(0, 0, 0.05), "")
    gui.set_font(node, "system")
    gui.set_scale(node, v3(Typography.prompt_scale, Typography.prompt_scale, 1))
    gui.set_pivot(node, pivot or gui.PIVOT_CENTER)
    if parent then gui.set_parent(node, parent, false) end
    return node
end

local function show(node, on)
    if node then gui.set_visible(node, on and true or false) end
end

-- The legend shows the stamp controls again after a change.
local function refresh_legend(self)
    self._prompt_revision = nil
end

function M.is_open(self)
    return self._stamps ~= nil and self._stamps.open == true
end

-- ---------------------------------------------------------------- stamps

-- Draws the shown stamps as glyph text nodes under ctx.map_root and returns
-- what the cursor may point at. Fast travel shows them without pointing.
function M.items(self, ctx)
    local st = state(self)
    local rows = (ctx.map_root and MapStamps.count() > 0) and MapStamps.shown() or {}
    local items = {}
    local inv = 1 / math.max(1e-6, ctx.scale or 1)
    local count = math.min(#rows, MapStamps.CAP)
    for i = 1, count do
        local row = rows[i]
        local node = st.nodes[i]
        if not node then
            node = text_node(ctx.map_root, gui.PIVOT_CENTER)
            st.nodes[i] = node
        end
        local px, py = ctx.world_to_image(row.x, row.y)
        if st.glyphs == nil then st.glyphs = {} end
        local glyph = DisplayText.render(row.glyph)
        if st.glyphs[i] ~= glyph then
            gui.set_text(node, glyph)
            st.glyphs[i] = glyph
        end
        gui.set_position(node, v3(px, py, 0.045))
        gui.set_scale(node, v3(inv * Typography.prompt_scale, inv * Typography.prompt_scale, 1))
        gui.set_color(node, color_of(row.color))
        show(node, true)
        local item = { px = px, py = py, kind = "stamp", stamp_index = row.index, snap = not ctx.fast_travel }
        if row.label then item.label = row.label else item.label_key = "map.stamp" end
        items[#items + 1] = item
    end
    for i = count + 1, #st.nodes do show(st.nodes[i], false) end
    return items
end

-- ---------------------------------------------------------------- palette

local function draw_palette(self, st, ctx)
    local pal = st.palette
    local cfg = MapStamps.settings()
    local icons = cfg.icons
    if not pal.back then
        pal.back = gui.new_box_node(v3(0, 0, 0.06), v3(1, 1, 0))
        gui.set_pivot(pal.back, gui.PIVOT_S)
        gui.set_color(pal.back, v4(0.05, 0.05, 0.08, 0.9))
        pal.caption = text_node(nil, gui.PIVOT_S)
    end
    local count = math.min(#icons, M.PALETTE_ICONS)
    -- A window of up to six icons that keeps the choice in view.
    local first = math.max(1, math.min(st.choice - math.floor(count / 2), #icons - count + 1))
    local step = 36
    local width = math.max(count * step + 16, Typography.map.palette_width)
    local area = Viewport.design_bounds("safe")
        or { min_x = 0, min_y = 0, max_x = ctx.screen_w, max_y = ctx.screen_h }
    local x = math.max(area.min_x + width * 0.5 + 8, math.min(area.max_x - width * 0.5 - 8, st.anchor.sx))
    local y = math.max(area.min_y + 8, math.min(area.max_y - 88, st.anchor.sy + 20))
    gui.set_position(pal.back, v3(x, y, 0.06))
    gui.set_size(pal.back, v3(width, 72, 0))
    show(pal.back, true)
    for slot = 1, M.PALETTE_ICONS do
        local node = pal.icons[slot]
        local index = first + slot - 1
        local icon = slot <= count and icons[index]
        if icon then
            if not node then
                node = text_node(nil, gui.PIVOT_CENTER)
                pal.icons[slot] = node
            end
            gui.set_text(node, DisplayText.render(icon.glyph))
            gui.set_position(node, v3(x - (count - 1) * step * 0.5 + (slot - 1) * step, y + 46, 0.065))
            local chosen = index == st.choice
            local c = color_of(icon.color)
            gui.set_color(node, chosen and c or v4(c.x, c.y, c.z, 0.45))
            gui.set_scale(node, chosen and v3(1.4, 1.4, 1) or v3(Typography.prompt_scale, Typography.prompt_scale, 1))
        end
        show(node, icon and true or false)
    end
    local caption
    if MapStamps.count() >= cfg.max then
        caption = DisplayText.ui("map.stamp_limit")
    else
        local icon = icons[st.choice]
        caption = icon and icon.label and DisplayText.render(icon.label) or DisplayText.ui("map.stamp")
    end
    gui.set_text(pal.caption, caption)
    gui.set_position(pal.caption, v3(x, y + 8, 0.065))
    show(pal.caption, true)
end

local function hide_palette(st)
    local pal = st.palette
    show(pal.back, false)
    show(pal.caption, false)
    for _, node in ipairs(pal.icons) do show(node, false) end
end

-- After the overlay moved the cursor: remember where it points (screen x, y,
-- the visible room under it and the stamp it snapped to) and draw the palette.
function M.update(self, ctx, hit, x, y, room_id)
    local st = state(self)
    local origin, scale = ctx.origin or { x = 0, y = 0 }, math.max(1e-6, ctx.scale or 1)
    local wx, wy = ctx.image_to_world((x - origin.x) / scale, (y - origin.y) / scale)
    local index = hit and hit.kind == "stamp" and hit.stamp_index or nil
    if index ~= st.hit_index then refresh_legend(self) end
    st.cursor = { sx = x, sy = y, wx = wx, wy = wy, room = room_id }
    st.hit_index = index
    st.fast_travel = ctx.fast_travel and true or false
    if st.open then draw_palette(self, st, ctx) else hide_palette(st) end
end

local function close(self, st)
    st.open = false
    hide_palette(st)
    refresh_legend(self)
end

local function open(self, st)
    local cfg = MapStamps.settings()
    st.open = true
    st.anchor = st.cursor
    st.choice = math.max(1, math.min(#cfg.icons, st.choice or 1))
    -- Pan stops while the palette is open (slice b G8-07 correction 8).
    self._pan_sticks, self._pan_keys, self._drag = {}, {}, nil
    refresh_legend(self)
end

local function notify(self)
    -- The minimap redraws from MapStamps.revision(); the legend may change.
    refresh_legend(self)
end

-- Palette and stamp input. Runs before the map's pan and zoom inputs, so the
-- open palette takes left and right, and every other input waits.
function M.input(self, action_id, action, menu_pressed)
    if menu_pressed == nil then menu_pressed = require("mvtk.ui.menu_nav").pressed(self, action_id, action) end
    if self.fast_travel_mode or not action then return false end
    local st = self._stamps
    if st and st.open then
        if action_id == nil then return true end
        if require("mvtk.ui.menu_nav").lifecycle(action_id) then return false end
        if not menu_pressed then return true end
        local cfg = MapStamps.settings()
        local count = #cfg.icons
        if InputPrompts.menu_matches("left", action_id) and count > 0 then
            st.choice = (st.choice - 2) % count + 1
        elseif InputPrompts.menu_matches("right", action_id) and count > 0 then
            st.choice = st.choice % count + 1
        elseif InputPrompts.menu_matches("confirm", action_id) then
            local icon = cfg.icons[st.choice]
            local anchor = st.anchor or {}
            -- At the limit the palette says so and places nothing.
            if icon and MapStamps.count() < cfg.max
                and MapStamps.place(icon.id, anchor.wx, anchor.wy, anchor.room) then
                close(self, st)
                notify(self)
            end
        elseif InputPrompts.menu_matches("back", action_id) or is_stamp_input(action_id) then
            close(self, st)
        end
        return true
    end
    if not is_stamp_input(action_id) then return false end
    -- A creator who made this input a menu command keeps the command.
    if InputPrompts.menu_matches("confirm", action_id) or InputPrompts.menu_matches("back", action_id) then
        return false
    end
    if not MapStamps.available() then return false end
    if action.pressed then
        st = state(self)
        if st.hit_index then
            MapStamps.remove(st.hit_index)
            st.hit_index = nil
            notify(self)
        elseif st.cursor then
            open(self, st)
        end
    end
    return true
end

-- The legend part for the X input: Stamp, or Remove stamp on a stamp.
function M.legend(self)
    if self.fast_travel_mode or not MapStamps.available() then return nil end
    local st = self._stamps
    local key = st and st.hit_index and "map.stamp_remove" or "map.stamp"
    return { key = "key_x", pad = "gamepad_rpad_left", text_key = key }
end

-- The legend while the palette is open.
function M.palette_legend()
    return {
        { key = { "key_left", "key_right" }, pad = { "gamepad_lpad_left", "gamepad_lpad_right" }, text_key = "map.select" },
        { command = "confirm", text_key = "map.stamp_place" },
        { command = "back", text_key = "map.cancel" },
    }
end

function M.hide(self)
    local st = self._stamps
    if not st then return end
    st.open, st.hit_index, st.cursor, st.anchor = false, nil, nil, nil
    for _, node in ipairs(st.nodes) do show(node, false) end
    hide_palette(st)
end

return M
