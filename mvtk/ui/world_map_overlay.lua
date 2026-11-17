local GeneratedText = require "mvtk.ui.generated_text"
-- World map pointing (G8-06c): the cursor, the info panel, region labels and
-- the legend's kinds on screen. Used by developer/ui/menus/world_map.gui_script,
-- which owns the scene; this module only creates and moves its own nodes.
--
--   Overlay.update(self, ctx) -> the item the cursor snapped to, or nil
--   Overlay.hide(self)        -- every overlay node, when the map closes
--   Overlay.reset(self)       -- forget cached room text after a map reload
--
-- ctx (filled by the script each frame):
--   screen_w, screen_h, origin {x, y}  root origin of the map image on screen
--   scale, fit                         screen px per image px; whole-world fit
--   cfg                                the world_map settings section
--   map_root                           parent of map-space nodes
--   image_to_world(px, py), world_to_image(wx, wy)
--   map_shift {x, y}                   baked-map = world + map_shift
--   vectors                            layout_vectors.lua data, or nil
--   rooms                              MINIMAP_MODULE.snapshot().rooms, or nil
--   items                              {{px, py (image), kind, label = source
--                                        text | label_key, params, snap,
--                                        state_key, legend}}; an item with
--                                        snap == false is only shown. A kind
--                                        not in M.KINDS lists in the legend
--                                        through legend {id, label (source
--                                        text, or key: a ui_text key),
--                                        color, shape} (G8-08c, G8-13b)
--   room_info(room_id)                 {found, total, more} or nil: the
--                                        "Items here" and "+N" lines
--   pointer {x, y} or nil              the mouse pointer once it moved
--   player_on_screen
--   legend_visible, legend_pos {x, y}  the button legend line
--   fast_travel                        true in fast travel (stamps are shown, not pointed at)
-- Player stamps (G8-07) are drawn and pointed at through
-- mvtk/ui/world_map_stamps.lua, which update calls with the same ctx.
-- Text: producers pass creator source text or ui_text keys; this module is the
-- displaying GUI and resolves them through DisplayText (Stage 4b T1-T10).
local MapView = require "mvtk.map.map_view"
local Discovery = require "mvtk.map.discovery"
local DisplayText = require "mvtk.ui.display_text"
local Viewport = require "mvtk.ui.viewport"
-- No cycle: Regions reaches the Tiled room registry only by name, at call time.
local Regions = require "mvtk.world.regions"

local Typography = require "developer.config.menu_typography"
local M = {}

-- Region, room title, items here, +N more, the snapped icon's label and its state.
M.INFO_LINES = 6
-- Legend kinds in display order: ui_text key and fallback colour.
M.KINDS = {
    { id = "player", key = "map.kind_player" },
    { id = "travel", key = "map.kind_travel" },
    { id = "save", key = "map.kind_save" },
    { id = "shop", key = "map.kind_shop" },
    { id = "boss", key = "map.kind_boss" },
    { id = "marker", key = "map.kind_marker" },
    { id = "screenshot", key = "map.kind_screenshot" },
}

local v3, v4 = vmath.vector3, vmath.vector4

local function state(self)
    local st = self._overlay
    if not st then
        st = { labels = {}, kinds = {}, info = {}, room_cache = {}, texts = {} }
        self._overlay = st
    end
    return st
end

local function text_node(parent, pivot)
    local node = GeneratedText.new(gui, "/developer/ui/menus/world_map.gui", v3(0, 0, 0.05), "")
    gui.set_font(node, "system")
    gui.set_scale(node, v3(Typography.prompt_scale, Typography.prompt_scale, 1))
    gui.set_pivot(node, pivot or gui.PIVOT_W)
    if parent then gui.set_parent(node, parent, false) end
    return node
end

local function box_node(size, color, parent)
    local node = gui.new_box_node(v3(0, 0, 0.05), size)
    gui.set_pivot(node, gui.PIVOT_CENTER)
    gui.set_color(node, color)
    if parent then gui.set_parent(node, parent, false) end
    return node
end

local function show(node, on)
    if node then gui.set_visible(node, on and true or false) end
end

-- Sets a text node's text only when it changed, and returns its measured width
-- (resource.get_text_metrics, as the HUD blocks measure their text).
local function set_text(st, node, text)
    local last = st.texts[node]
    if last and last.text == text then return last.width end
    gui.set_text(node, text)
    local ok, metrics = pcall(function()
        return GeneratedText.metrics(gui.get_font_resource(gui.get_font(node)), text, nil, resource)
    end)
    local width = ok and type(metrics) == "table" and tonumber(metrics.width) or #text * 9
    width = width * Typography.prompt_scale
    st.texts[node] = { text = text, width = width }
    return width
end

-- ---------------------------------------------------------------- cursor

local function draw_cursor(st, x, y, snapped)
    if not st.cursor then
        local color = v4(1, 1, 1, 0.85)
        st.cursor = { box_node(v3(22, 2, 0), color), box_node(v3(2, 22, 0), color) }
    end
    local color = snapped and v4(0.25, 0.85, 1.0, 1.0) or v4(1, 1, 1, 0.85)
    for _, node in ipairs(st.cursor) do
        gui.set_position(node, v3(x, y, 0.05))
        gui.set_color(node, color)
        show(node, true)
    end
end

-- ---------------------------------------------------------------- rooms

-- Region name and room title (source text) for a room id, cached per id:
-- the registry copies its metadata table on every call (R2 S22).
local function room_text(st, id)
    local row = st.room_cache[id]
    if row then return row end
    local info = Regions.info(Regions.of_room(id))
    row = { region = info and info.name ~= "" and info.name or nil, title = Regions.room_title(id) }
    st.room_cache[id] = row
    return row
end

-- The room id under image point (px, py), named only where the player can see
-- it (G8-06 slice b correction 14). Concealed rooms are never named.
local function room_under(ctx, px, py)
    local wx, wy = ctx.image_to_world(px, py)
    local room
    if ctx.vectors then
        local shift = ctx.map_shift or {}
        room = MapView.room_at(ctx.vectors, wx + (shift.x or 0), wy + (shift.y or 0))
    else
        room = MapView.room_in_bounds(ctx.rooms, wx, wy)
    end
    local id = room and room.id
    if not id or Discovery.is_secret_hidden(nil, nil, id) then return nil end
    if not Discovery.is_visible(wx, wy, id) then return nil end
    return id
end

-- ---------------------------------------------------------------- info panel

local function item_text(item)
    if not item then return nil end
    if item.label_key then return DisplayText.ui(item.label_key, item.params) end
    if type(item.label) == "string" and item.label:match("%S") then return DisplayText.render(item.label) end
    for _, kind in ipairs(M.KINDS) do
        if kind.id == item.kind then return DisplayText.ui(kind.key) end
    end
    return nil
end

local function draw_info(st, ctx, room_id, item)
    local counts = room_id and ctx.room_info and ctx.room_info(room_id) or nil
    -- Redrawn only when the room, its counts, the item, the language or the screen changes.
    local key = tostring(room_id) .. "|" .. tostring(item and item.kind) .. "|" .. tostring(item and item.label)
        .. "|" .. tostring(item and item.label_key) .. "|" .. tostring(item and item.state_key)
        .. "|" .. tostring(counts and counts.found) .. "/" .. tostring(counts and counts.total)
        .. "+" .. tostring(counts and counts.more) .. "|" .. DisplayText.revision()
        .. "|" .. tostring(ctx.screen_w) .. "x" .. tostring(ctx.screen_h)
    if st.info_key == key then return end
    st.info_key = key
    local lines = {}
    if room_id then
        local row = room_text(st, room_id)
        if row.region then lines[#lines + 1] = DisplayText.render(row.region) end
        if row.title then lines[#lines + 1] = DisplayText.render(row.title) end
    end
    -- G8-08c: "Items here: 3 of 5" for a visited room, and the icons the pool could not draw.
    if counts and counts.total then
        lines[#lines + 1] = DisplayText.ui("map.items_here", { found = counts.found, total = counts.total })
    end
    if counts and (counts.more or 0) > 0 then
        lines[#lines + 1] = DisplayText.ui("map.more", { count = counts.more })
    end
    local text = item_text(item)
    if text then lines[#lines + 1] = text end
    if item and item.state_key then lines[#lines + 1] = DisplayText.ui(item.state_key) end
    local info = st.info
    if not info.back then
        info.back = gui.new_box_node(v3(0, 0, 0.045), v3(1, 1, 0))
        gui.set_pivot(info.back, gui.PIVOT_NW)
        gui.set_color(info.back, v4(0.05, 0.05, 0.08, 0.8))
        for i = 1, M.INFO_LINES do info[i] = text_node(nil, gui.PIVOT_NW) end
    end
    local area = Viewport.design_bounds("safe")
        or { min_x = 0, min_y = 0, max_x = ctx.screen_w, max_y = ctx.screen_h }
    local x, y = area.min_x + 16, area.max_y - 16
    local width = 0
    for i = 1, M.INFO_LINES do
        local line = lines[i]
        local node = info[i]
        if line then
            width = math.max(width, set_text(st, node, line))
            gui.set_position(node, v3(x + 8, y - 6 - (i - 1) * 24, 0.05))
        end
        show(node, line ~= nil)
    end
    local count = math.min(#lines, M.INFO_LINES)
    if count > 0 then
        gui.set_position(info.back, v3(x, y, 0.045))
        gui.set_size(info.back, v3(width + 16, count * 24 + 8, 0))
    end
    show(info.back, count > 0)
end

-- ---------------------------------------------------------------- region labels

local function known_room(id)
    if Discovery.is_secret_hidden(nil, nil, id) then return false end
    if not Discovery.enabled() then return true end
    return Discovery.is_visited(id) or Discovery.is_revealed(id)
end

local function draw_labels(st, ctx)
    local cfg = ctx.cfg and ctx.cfg.labels or {}
    local list = {}
    if cfg.regions ~= false and ctx.rooms then
        -- Rebuilt only when discovery, the room list or the language changes.
        local key = tostring(Discovery.revision()) .. ":" .. #ctx.rooms .. ":" .. DisplayText.revision()
        if st.labels_key ~= key then
            st.labels_key = key
            local max = math.min(MapView.CAPS.labels, math.floor(tonumber(cfg.max) or MapView.CAPS.labels))
            st.label_list = MapView.region_labels(ctx.rooms, known_room, Regions, max)
            for _, row in ipairs(st.label_list) do row.text = DisplayText.render(row.name) end
        end
        list = st.label_list or {}
    end
    local alpha = MapView.label_alpha(ctx.scale, ctx.fit, cfg)
    local inv = 1 / math.max(1e-6, ctx.scale or 1)
    for i = 1, math.max(#list, #st.labels) do
        local row, node = list[i], st.labels[i]
        if row and alpha > 0 then
            if not node then
                node = text_node(ctx.map_root, gui.PIVOT_CENTER)
                st.labels[i] = node
            end
            local px, py = ctx.world_to_image(row.x, row.y)
            set_text(st, node, row.text)
            gui.set_position(node, v3(px, py, 0.04))
            gui.set_scale(node, v3(inv * Typography.prompt_scale, inv * Typography.prompt_scale, 1))
            gui.set_color(node, v4(1, 1, 1, alpha))
            show(node, true)
        else
            show(node, false)
        end
    end
end

-- ---------------------------------------------------------------- legend kinds

local function draw_kinds(st, ctx, present)
    local cfg = ctx.cfg or {}
    local colors = cfg.colors or {}
    local fallback = {
        player = colors.player or v4(1.0, 0.92, 0.20, 0.95), travel = colors.icon_bench,
        save = colors.icon_bench, shop = colors.icon_shop, boss = colors.icon_boss,
        marker = colors.icon_custom, screenshot = v4(1.0, 0.8, 0.2, 0.95),
    }
    local pos = ctx.legend_pos or { x = 16, y = 32 }
    local x, y = pos.x, Typography.map.kinds_y
    local slot = 0
    -- Fixed kinds first, then G8-08c's map_icons rows (kinds and icons on
    -- screen), each with its configured shape, colour and label.
    local rows = {}
    for _, kind in ipairs(M.KINDS) do
        if present[kind.id] then rows[#rows + 1] = kind end
    end
    for _, legend in ipairs(present.extra or {}) do rows[#rows + 1] = legend end
    for _, kind in ipairs(rows) do
        if ctx.legend_visible and slot * 2 + 2 <= MapView.CAPS.legend then
            slot = slot + 1
            local row = st.kinds[slot]
            if not row then
                row = { swatch = { { node = box_node(v3(10, 10, 0), v4(1, 1, 1, 1)), type = "box" } },
                    text = text_node(nil, gui.PIVOT_W) }
                st.kinds[slot] = row
            end
            local label, swatch
            if kind.key and not kind.shape then
                label = DisplayText.ui(kind.key)
                swatch = row.swatch[1].type == "box" and row.swatch[1].node
                    or require("mvtk.ui.world_map_items").shape_node(row.swatch, 1, nil, "square", "normal", 10)
                gui.set_color(swatch, kind.id == "travel" and v4(0.25, 0.85, 1.0, 1.0)
                    or fallback[kind.id] or v4(1, 1, 1, 1))
            else
                -- A map_icons row: source label, or a ui_text key (the goal target).
                label = kind.key and DisplayText.ui(kind.key) or DisplayText.render(kind.label or "")
                swatch = require("mvtk.ui.world_map_items").shape_node(row.swatch, 1, nil, kind.shape, "normal", 10)
                gui.set_color(swatch, kind.color or v4(1, 1, 1, 1))
            end
            local width = set_text(st, row.text, label)
            if x + 30 + width > Typography.map.legend_x + Typography.map.legend_width then
                x, y = pos.x, y + Typography.map.kinds_line_height
            end
            gui.set_position(swatch, v3(x + 5, y, 0.05))
            gui.set_position(row.text, v3(x + 14, y, 0.05))
            show(swatch, true); show(row.text, true)
            x = x + 30 + width
        end
    end
    for i = slot + 1, #st.kinds do show(st.kinds[i].swatch[1].node, false); show(st.kinds[i].text, false) end
end

-- ---------------------------------------------------------------- update

function M.update(self, ctx)
    local st = state(self)
    local origin, scale = ctx.origin or { x = 0, y = 0 }, ctx.scale or 1
    local area = Viewport.design_bounds("picture")
        or { min_x = 0, min_y = 0, max_x = ctx.screen_w, max_y = ctx.screen_h }
    local present, items = {}, {}
    local Stamps = require "mvtk.ui.world_map_stamps"
    local all = {}
    for _, item in ipairs(ctx.items or {}) do all[#all + 1] = item end
    for _, item in ipairs(Stamps.items(self, ctx)) do all[#all + 1] = item end
    for _, item in ipairs(all) do
        item.sx, item.sy = origin.x + item.px * scale, origin.y + item.py * scale
        if item.sx >= area.min_x and item.sx <= area.max_x and item.sy >= area.min_y and item.sy <= area.max_y then
            local kind = item.kind or "marker"
            if item.legend and not present[kind] then
                local extra = present.extra or {}
                present.extra = extra
                extra[#extra + 1] = item.legend
            end
            present[kind] = true
            if item.snap ~= false then items[#items + 1] = item end
        end
    end
    if present.extra then table.sort(present.extra, function(a, b) return tostring(a.id) < tostring(b.id) end) end
    if ctx.player_on_screen then present.player = true end

    local cursor = ctx.cfg and ctx.cfg.cursor or {}
    local x, y = MapView.cursor_point(ctx.pointer, ctx.screen_w, ctx.screen_h)
    local hit = MapView.nearest(items, x, y, tonumber(cursor.snap_px) or 24)
    if hit then x, y = hit.sx, hit.sy end
    draw_cursor(st, x, y, hit ~= nil)

    local room_id = room_under(ctx, (x - origin.x) / scale, (y - origin.y) / scale)
    if cursor.info_panel ~= false then
        draw_info(st, ctx, room_id, hit)
    else
        draw_info(st, ctx, nil, nil)
    end
    draw_labels(st, ctx)
    draw_kinds(st, ctx, present)
    Stamps.update(self, ctx, hit, x, y, room_id)
    st.room_id, st.hit = room_id, hit
    return hit
end

function M.hide(self)
    local st = self._overlay
    if not st then return end
    for _, node in ipairs(st.cursor or {}) do show(node, false) end
    show(st.info.back, false)
    for i = 1, M.INFO_LINES do show(st.info[i], false) end
    st.info_key = nil
    for _, node in ipairs(st.labels) do show(node, false) end
    for _, row in ipairs(st.kinds) do show(row.swatch[1].node, false); show(row.text, false) end
    st.hit, st.room_id = nil, nil
    require("mvtk.ui.world_map_stamps").hide(self)
end

-- Forgets cached room text (a reloaded map can rename rooms).
function M.reset(self)
    local st = self._overlay
    if st then st.room_cache, st.labels_key, st.info_key = {}, nil, nil end
end

return M
