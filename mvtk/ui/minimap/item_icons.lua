-- Minimap item and station icons (G8-08d): census icons for the current room and
-- its direct neighbours, drawn as colour shapes (minimap.gui has no font).
-- Used by developer/ui/game/minimap.gui_script, which owns the scene; this module
-- creates and moves only its own nodes, at most map_icons.lua minimap.max_icons.
--
--   Icons.collect(self, center_room) -> visible icon records, cached
--   Icons.sync(self, ctx)            -- places the pool for this frame
--   Icons.hide(self)                 -- hides every icon
--
-- Every object comes from mvtk/map/map_tracking.lua over the prepared census, so
-- the same rules as the world map apply (seen, hide_on_map, gone, collected
-- style) and a station's icon does not depend on its room being loaded
-- (STAGE_7 D-S7B-1, D-S7B-2). Two kinds keep their existing minimap drawing and
-- are skipped here, so nothing is drawn twice: placed Map Markers (the marker
-- registry, with its own discovery radius and facing) and gates (gate_markers.lua).
local MapTracking = require "mvtk.map.map_tracking"
local Census = require "mvtk.world.census"
local WorldMapItems = require "mvtk.ui.world_map_items"

local M = {}

M.SKIP_KINDS = { map_marker = true }
M.SKIP_TYPES = { gate = true }

local function state(self)
    local st = self._minimap_icons
    if not st then
        st = { nodes = {} }
        self._minimap_icons = st
    end
    return st
end

-- The rooms whose icons show: the current room first, then its neighbours in
-- the layout's order. A room id appears once.
function M.rooms(center)
    if center == nil or center == "" then return {} end
    local out, seen = { center }, { [center] = true }
    local Rooms = require "mvtk.map.streaming.room_manager"
    local ok, edges = pcall(Rooms.get_room_neighbors, center)
    for _, edge in ipairs(ok and type(edges) == "table" and edges or {}) do
        local id = type(edge) == "table" and (edge.id or edge.room or edge.neighbor) or edge
        if type(id) == "string" and id ~= "" and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local function vec4(c, alpha)
    c = c or {}
    local r, g, b, a = c.x or 1, c.y or 1, c.z or 1, (c.w or 1) * (alpha or 1)
    if vmath and vmath.vector4 then return vmath.vector4(r, g, b, a) end
    return { x = r, y = g, z = b, w = a }
end

-- Visible icons of the current room and its neighbours, at most max_icons,
-- rebuilt only when the census (flags and discovery), the settings or the
-- current room changes. Never per frame.
function M.collect(self, center)
    local st = state(self)
    local census_rev = Census.revision()
    local settings_rev = require("developer.config.runtime_settings").revision()
    if st.list and st.census_rev == census_rev and st.settings_rev == settings_rev and st.center == center then
        return st.list
    end
    local cfg = MapTracking.settings()
    local mini = type(cfg.minimap) == "table" and cfg.minimap or {}
    local cap = math.max(0, math.floor(tonumber(mini.max_icons) or 0))
    local list = {}
    if mini.show ~= false and cap > 0 then
        local rooms = MapTracking.index().rooms
        for _, room in ipairs(M.rooms(center)) do
            for _, entry in ipairs(rooms[room] or {}) do
                if #list >= cap then break end
                if not M.SKIP_KINDS[entry.kind] and not M.SKIP_TYPES[entry.type]
                    and MapTracking.visible(entry, "minimap") then
                    local look = MapTracking.appearance(entry)
                    list[#list + 1] = { wx = entry.wx, wy = entry.wy, room = room, id = entry.id,
                        shape = look.shape, style = look.style, color = vec4(look.color, look.alpha) }
                end
            end
        end
    end
    st.list, st.census_rev, st.settings_rev, st.center = list, census_rev, settings_rev, center
    return list
end

-- ctx: parent (the markers' container), center_id (current room), to_map(wx, wy),
-- center_x, center_y, zoom, offset_x, offset_y, pixel_snap, size (icon pixels).
-- Places one node per visible icon the same way custom_markers.lua places markers,
-- shaped by the world map's builder at the minimap's marker depth.
function M.sync(self, ctx)
    local st = state(self)
    local list = M.collect(self, ctx.center_id)
    local size = tonumber(ctx.size) or 6
    local zoom = ctx.zoom or 1
    for i, rec in ipairs(list) do
        local map_x, map_y = ctx.to_map(rec.wx, rec.wy)
        local x = (map_x - (ctx.center_x or 0)) * zoom + (ctx.offset_x or 0)
        local y = (map_y - (ctx.center_y or 0)) * zoom + (ctx.offset_y or 0)
        if ctx.pixel_snap then x, y = math.floor(x + 0.5), math.floor(y + 0.5) end
        local node = WorldMapItems.shape_node(st.nodes, i, ctx.parent, rec.shape, rec.style, size, 0.027)
        gui.set_position(node, vmath.vector3(x, y, 0.027))
        gui.set_color(node, rec.color)
        gui.set_visible(node, true)
    end
    for i = #list + 1, #st.nodes do gui.set_visible(st.nodes[i].node, false) end
    st.shown = #list
end

function M.hide(self)
    local st = self._minimap_icons
    if not st then return end
    for _, rec in ipairs(st.nodes) do gui.set_visible(rec.node, false) end
    st.shown = 0
end

return M
