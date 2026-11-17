-- World map item tracking (G8-08c): census icons, the room status overlay,
-- station icons for the POI pool and the info panel's item lines. Used by
-- developer/ui/menus/world_map.gui_script, which owns the scene; this module
-- creates and moves only its own nodes and its one texture.
--
--   Items.collect(self, ctx)        -> {stations = {...}, icons = {...}}, cached
--   Items.stations(self, ctx)       -> station, marker and POI icons for the POI pool
--   Items.covers(id)                -> true when the census draws registry marker `id`
--   Items.draw(self, ctx)           -> cursor items for the icons drawn this frame
--   Items.update_overlay(self, ctx) -- the room tint and "items left" dots on
--                                      self.status_node, which the script creates
--   Items.room_info(self, room_id)  -> {found, total, more} for the info panel
--   Items.invalidate(self)          -- on map open: rebuild from the census
--   Items.hide(self)                -- every icon and the overlay, on close
--
-- Every object comes from mvtk/map/map_tracking.lua over the prepared census,
-- so rooms that are not loaded keep their icons (STAGE_7 D-S7B-1). Item icons
-- show only at detail zoom; stations, markers and POIs use the POI pool at
-- every zoom; the overlay shows at overview zoom (slice b G8-08 correction 5).
-- Labels are source text and state lines are ui_text keys: only the overlay
-- (the displaying GUI) resolves them.
local MapTracking = require "mvtk.map.map_tracking"
local MapView = require "mvtk.map.map_view"
local MapRaster = require "mvtk.map.map_raster"
local Discovery = require "mvtk.map.discovery"
local Census = require "mvtk.world.census"
local DynamicTexture = require "mvtk.ui.dynamic_texture"

local M = {}

M.ICON_PX = 8                          -- item icon size in screen pixels
M.MAX_ICONS = MapView.CAPS.items - 1    -- the items pool's last node is the overlay
M.TEXTURE = "world_map_status"
M.MAX_TEXTURE_PX = 1024                 -- the overlay's longest side
-- Census kinds drawn through the POI pool (labels, facing, every zoom).
M.STATIONS = { travel = true, shop = true, upgrade_station = true, bank = true, skill_trainer = true,
    offering_altar = true, npc = true, health_station = true, energy_station = true, map_station = true,
    teleporter = true, map_marker = true, poi = true }

local v3, v4 = vmath.vector3, vmath.vector4

local function state(self)
    local st = self._items
    if not st then
        st = { icons = {}, epoch = 0, info = {} }
        self._items = st
    end
    return st
end

local function runtime_revision()
    return require("developer.config.runtime_settings").revision()
end

function M.invalidate(self)
    local st = state(self)
    st.epoch = st.epoch + 1
    st.list_key, st.draw_key, st.overlay_key, st.info = nil, nil, nil, {}
    MapTracking.invalidate()
end

-- The ui_text key of an entry's state line, or nil (G8-08 step 6).
function M.state_key(entry)
    if entry.kind == "barrier" then
        return MapTracking.collected(entry) and "map.state_open" or "map.state_locked"
    end
    if not MapTracking.collected(entry) then return nil end
    if entry.kind == "chest" then return "map.state_opened"
    elseif entry.kind == "boss" then return "map.state_defeated"
    elseif entry.kind == "trial" then return "map.state_cleared"
    elseif entry.type == "offering_altar" then return "map.state_used"
    elseif entry.kind == "item" or entry.kind == "lore" or entry.kind == "secret" then return "map.state_collected" end
    return nil
end

-- Legend row of an entry: the icon id it uses, else its type or kind row.
local function legend_of(entry, cfg)
    local icon_id = MapTracking.icon_id(entry)
    local icon = (cfg.icons or {})[icon_id or ""]
    if icon then return "icon_" .. icon_id, icon.label end
    local kinds = cfg.kinds or {}
    local key = kinds[entry.type] and entry.type or entry.kind
    return "kind_" .. tostring(key), (kinds[key] or {}).label
end

local function vec4(c, alpha)
    c = c or {}
    return v4(c.x or 1, c.y or 1, c.z or 1, (c.w or 1) * (alpha or 1))
end

-- Visible entries split into stations (POI pool) and icons (item pool),
-- rebuilt only when the census, settings, marker registry or epoch changes.
-- ctx.poi_bosses: developer/config/poi.lua bosses by room (correction 11);
-- ctx.marker_version: the minimap snapshot's world_marker_version.
function M.collect(self, ctx)
    ctx = ctx or {}
    local st = state(self)
    local key = table.concat({ Census.revision(), runtime_revision(), tostring(ctx.marker_version), st.epoch,
        require("mvtk.game.goals").revision() }, ":")
    if st.list_key == key then return st.list end
    local cfg = MapTracking.settings()
    local bosses = ctx.poi_bosses or {}
    local list = { stations = {}, icons = {} }
    for _, entry in ipairs(MapTracking.index().list) do
        -- A layout-tagged boss POI already marks that room: no second boss icon.
        local doubled = entry.kind == "boss" and bosses[entry.room] ~= nil
        if not doubled and MapTracking.visible(entry, "world_map") then
            local look = MapTracking.appearance(entry)
            local legend_id, legend_label = legend_of(entry, cfg)
            local rec = { entry = entry, wx = entry.wx, wy = entry.wy, room = entry.room,
                shape = look.shape, style = look.style, color = vec4(look.color, look.alpha),
                label = look.label, facing = entry.facing, state_key = M.state_key(entry),
                legend = { id = legend_id, label = legend_label or "", shape = look.shape } }
            rec.legend.color = rec.color
            local target = M.STATIONS[entry.kind] and list.stations or list.icons
            target[#target + 1] = rec
        end
    end
    local goal_rec = M.goal_target_record(cfg)
    if goal_rec then list.stations[#list.stations + 1] = goal_rec end
    st.list, st.list_key, st.info = list, key, {}
    return list
end

-- The revealed goal target (G8-13b) as a POI record: every zoom, whatever
-- item_tracking says. Its label is the goal's source title; the legend row
-- uses the map_icons goal_target label, else the ui_text key.
function M.goal_target_record(cfg)
    local entry, goal = MapTracking.goal_target()
    if not entry then return nil end
    local row = ((cfg or MapTracking.settings()).kinds or {}).goal_target or {}
    local color = MapTracking.color(row.color) or MapTracking.color({ r = 1, g = 0.95, b = 0.35, a = 1 })
    local shape = row.shape or "ring"
    local label = type(row.label) == "string" and row.label ~= "" and row.label or nil
    local rec = { entry = entry, wx = entry.wx, wy = entry.wy, room = entry.room, shape = shape, style = "normal",
        color = vec4(color, 1), label = goal.title or "", goal_id = goal.id,
        legend = { id = "goal_target", label = label, key = not label and "map.legend_goal_target" or nil, shape = shape } }
    rec.legend.color = rec.color
    return rec
end

function M.stations(self, ctx) return M.collect(self, ctx).stations end

-- A registered marker the census already lists is drawn from the census only.
function M.covers(id)
    return id ~= nil and MapTracking.index().registry[id] ~= nil
end

-- Creates (or re-creates, when the shape needs another node type) node `i` of
-- `holder` and gives it the shape: box; box turned 45 degrees for a diamond;
-- pie for a circle; pie with an inner radius for a ring or the outline style
-- (gui.new_pie_node, gui.set_inner_radius, gui.set_euler: gui_script.cpp 1.14.0).
-- holder is an array of {node, type}; z is the new node's depth (default 0.02).
-- The minimap's icons (mvtk/ui/minimap/item_icons.lua) use it too.
function M.shape_node(holder, i, parent, shape, style, size, z)
    local pie = shape == "circle" or shape == "ring" or style == "outline"
    local want = pie and "pie" or "box"
    local rec = holder[i]
    if rec and rec.type ~= want then
        gui.delete_node(rec.node)
        rec = nil
    end
    if not rec then
        z = z or 0.02
        local node = pie and gui.new_pie_node(v3(0, 0, z), v3(size, size, 0))
            or gui.new_box_node(v3(0, 0, z), v3(size, size, 0))
        gui.set_pivot(node, gui.PIVOT_CENTER)
        if parent then gui.set_parent(node, parent, false) end
        rec = { node = node, type = want }
        holder[i] = rec
    end
    local node = rec.node
    if pie then
        gui.set_size(node, v3(size, size, 0))
        gui.set_inner_radius(node, (shape == "ring" or style == "outline") and size * 0.3 or 0)
        gui.set_euler(node, v3(0, 0, 0))
    else
        local side = shape == "diamond" and size * 0.75 or size
        gui.set_size(node, v3(side, side, 0))
        gui.set_euler(node, v3(0, 0, shape == "diamond" and 45 or 0))
    end
    return node
end

-- Draws the item icons inside the view at detail zoom, at most M.MAX_ICONS;
-- icons past the pool count per room for the info panel's "+N" line.
-- ctx: map_root, scale, detail, world_to_image(wx, wy), view (image rect or
-- nil), fast_travel, plus collect's fields. Returns the cursor items.
function M.draw(self, ctx)
    local st = state(self)
    local list = M.collect(self, ctx)
    local view = ctx.view
    local scale = math.max(1e-6, ctx.scale or 1)
    local key = table.concat({ st.list_key, ctx.detail and 1 or 0, scale, ctx.fast_travel and 1 or 0,
        view and math.floor(view.min_x) or "", view and math.floor(view.min_y) or "",
        view and math.floor(view.max_x) or "", view and math.floor(view.max_y) or "" }, ":")
    if st.draw_key == key then return st.items end
    local items, overflow, shown = {}, {}, 0
    if ctx.detail then
        local size = M.ICON_PX / scale
        for _, rec in ipairs(list.icons) do
            local px, py = ctx.world_to_image(rec.wx, rec.wy)
            if not view or (px >= view.min_x and px <= view.max_x and py >= view.min_y and py <= view.max_y) then
                if shown < M.MAX_ICONS then
                    shown = shown + 1
                    local node = M.shape_node(st.icons, shown, ctx.map_root, rec.shape, rec.style, size)
                    gui.set_position(node, v3(px, py, 0.02))
                    gui.set_color(node, rec.color)
                    gui.set_visible(node, true)
                    items[#items + 1] = { px = px, py = py, kind = rec.legend.id, label = rec.label,
                        state_key = rec.state_key, legend = rec.legend, snap = not ctx.fast_travel }
                else
                    overflow[rec.room] = (overflow[rec.room] or 0) + 1
                end
            end
        end
    end
    for i = shown + 1, #st.icons do gui.set_visible(st.icons[i].node, false) end
    st.items, st.shown, st.overflow, st.draw_key, st.info = items, shown, overflow, key, {}
    return items
end

-- ---------------------------------------------------------------- overlay

local function bytes(c, fallback)
    c = type(c) == "table" and c or fallback or {}
    local function n(v, d) v = tonumber(v); if v == nil then v = d end; return v * 255 end
    return { n(c.r or c.x, 1), n(c.g or c.y, 1), n(c.b or c.z, 1), n(c.a or c.w, 1) }
end

-- rooms: {{id, poly = {x1, y1, ...}}} in overview image pixels. Visited,
-- unconcealed rooms whose counted items are all found get the tint; visited
-- rooms with items left get a dot at their centre (D-S7B-6: an unfound secret
-- is never counted). Returns MapRaster.status shapes and the texture size.
-- opts: tint (bytes or nil), dot (bytes or nil).
function M.overlay_shapes(rooms, map_w, map_h, opts)
    opts = opts or {}
    local f = math.min(1, M.MAX_TEXTURE_PX / math.max(1, map_w, map_h))
    local w, h = math.max(1, math.ceil(map_w * f)), math.max(1, math.ceil(map_h * f))
    local shapes = {}
    for _, room in ipairs(rooms or {}) do
        local id, poly = room.id, room.poly or {}
        if id and #poly >= 6 and not Discovery.is_secret_hidden(nil, nil, id) then
            local status = MapTracking.room_status(id)
            if status.visited then
                local xs, ys = {}, {}
                local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
                for i = 1, math.floor(#poly / 2) do
                    local x, y = poly[i * 2 - 1] * f, poly[i * 2] * f
                    xs[i], ys[i] = x, y
                    x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
                end
                if opts.tint and status.complete then shapes[#shapes + 1] = { xs = xs, ys = ys, color = opts.tint } end
                if opts.dot and status.found < status.total then
                    local r = math.max(1, math.min(4, math.min(x1 - x0, y1 - y0) * 0.15))
                    local cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
                    shapes[#shapes + 1] = { xs = { cx - r, cx + r, cx + r, cx - r },
                        ys = { cy - r, cy - r, cy + r, cy + r }, color = opts.dot }
                end
            end
        end
    end
    return shapes, w, h, f
end

-- Room outlines in overview image pixels: layout_vectors.lua polygons when the
-- map has them, else the minimap snapshot's room bounds.
local function room_polys(ctx)
    local out = {}
    if ctx.vectors and ctx.vector_to_image then
        for _, room in ipairs(ctx.vectors.rooms or {}) do
            local poly, img = room.poly or {}, {}
            for i = 1, #poly - 1, 2 do img[i], img[i + 1] = ctx.vector_to_image(poly[i], poly[i + 1]) end
            out[#out + 1] = { id = room.id, poly = img }
        end
    elseif ctx.rooms and ctx.world_to_image then
        for _, room in ipairs(ctx.rooms) do
            local b = room.r
            if b then
                local ax, ay = ctx.world_to_image(b.min_x, b.min_y)
                local bx, by = ctx.world_to_image(b.max_x, b.max_y)
                out[#out + 1] = { id = room.id, poly = { ax, ay, bx, ay, bx, by, ax, by } }
            end
        end
    end
    return out
end

-- Shows the overlay at overview zoom and rebuilds its texture when the census
-- or discovery (Census.revision), settings or the map changes (step 3).
-- ctx: node, detail, map_w, map_h, vectors + vector_to_image, or rooms +
-- world_to_image.
function M.update_overlay(self, ctx)
    local st, node = state(self), ctx.node
    if not node then return false end
    local cfg = MapTracking.settings()
    local complete = cfg.room_complete or {}
    local tint_on, dots_on = complete.enabled ~= false, MapTracking.tracking_on()
    if ctx.detail or st.overlay_failed or not (tint_on or dots_on) then
        gui.set_enabled(node, false)
        return false
    end
    local rooms = ctx.vectors and "v" or #(ctx.rooms or {})
    local key = table.concat({ Census.revision(), runtime_revision(), st.epoch, ctx.map_w, ctx.map_h, rooms }, ":")
    if st.overlay_key ~= key then
        st.overlay_key = key
        local dot = ((cfg.kinds or {}).item or {}).color
        local shapes, w, h = M.overlay_shapes(room_polys(ctx), ctx.map_w, ctx.map_h, {
            tint = tint_on and bytes(complete.color) or nil, dot = dots_on and bytes(dot) or nil })
        st.overlay_empty = #shapes == 0
        if not st.overlay_empty then
            if not DynamicTexture.update(M.TEXTURE, w, h, MapRaster.status(shapes, w, h), { format = "rgba", flip = true }) then
                -- Out of texture resources: no overlay for the rest of the session.
                st.overlay_failed = true
                gui.set_enabled(node, false)
                return false
            end
            gui.set_texture(node, M.TEXTURE)
            gui.set_position(node, v3(0, 0, 0))
            gui.set_size(node, v3(ctx.map_w, ctx.map_h, 0))
        end
    end
    gui.set_enabled(node, not st.overlay_empty)
    return not st.overlay_empty
end

-- ---------------------------------------------------------------- info panel

-- "Items here" counts for a visited room while tracking is on, and the icons
-- the pool could not draw there. Cached until the census or the drawing changes.
function M.room_info(self, room_id)
    if not room_id then return nil end
    local st = state(self)
    local row = st.info[room_id]
    if row then return row end
    row = { more = (st.overflow or {})[room_id] or 0 }
    if MapTracking.tracking_on() then
        local status = MapTracking.room_status(room_id)
        if status.visited and status.total > 0 then row.found, row.total = status.found, status.total end
    end
    st.info[room_id] = row
    return row
end

function M.hide(self)
    local st = self._items
    if not st then return end
    for _, rec in ipairs(st.icons) do gui.set_visible(rec.node, false) end
    st.draw_key = nil
    if self.status_node then gui.set_enabled(self.status_node, false) end
end

return M
