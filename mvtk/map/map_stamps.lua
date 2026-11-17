-- Player map stamps (G8-07): reminder stamps players leave on the world map,
-- such as a star, '!' or '?'. Saved per slot by the versioned provider
-- 'map_stamps' (v1, order 55); a new game starts with none.
--
-- A stamp is {icon, room, x, y}: a palette id from world_map_settings.lua
-- `stamps.icons`, a room id and an integer position relative to that room's
-- collection origin (RoomGeometry.compute_spawn_xy), so a re-exported layout
-- keeps every stamp in its room. Saves hold ids and numbers only; ids are
-- never shown.
--
--   MapStamps.settings()              -- the stamps block, cached per settings revision
--   MapStamps.add(icon, room, x, y)   -- true, or false and a reason ("limit", ...)
--   MapStamps.place(icon, wx, wy, room)-- add at a world point (attach below)
--   MapStamps.attach(wx, wy, room)    -- room, x, y for a world point
--   MapStamps.remove(index), list(), count(), revision()
--   MapStamps.at(wx, wy, radius)      -- index of the nearest shown stamp
--   MapStamps.shown()                 -- the stamps to draw, with world positions
--
-- RoomManager, RoomGeometry and Discovery are required at call time, so this
-- module loads (and registers its provider) before the room system exists.
local Checkpoint = require "mvtk.core.checkpoint"

local M = {}

-- The world map's stamp node pool (mvtk/map/map_view.lua POOLS "stamps":
-- 64 stamps and 8 palette nodes). `max` is clamped to this.
M.CAP = 64
M.DEFAULT_MAX = 32

local state = { stamps = {} }
local serial, session = 0, 0
local config, config_revision
local shown_key, shown_list

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function round(value) return math.floor(value + 0.5) end

local function text(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- Correction 6: keep only {string icon, string room, number x, number y};
-- a row whose icon left the palette is kept (and hidden while it is gone).
local function sanitize(data)
    local out = {}
    local rows = type(data) == "table" and type(data.stamps) == "table" and data.stamps or {}
    for _, row in ipairs(rows) do
        if #out >= M.CAP then break end
        if type(row) == "table" and text(row.icon) and text(row.room) and finite(row.x) and finite(row.y) then
            out[#out + 1] = { icon = row.icon, room = row.room, x = round(row.x), y = round(row.y) }
        end
    end
    return { stamps = out }
end

local function copy_state()
    local out = {}
    for i, row in ipairs(state.stamps) do
        out[i] = { icon = row.icon, room = row.room, x = row.x, y = row.y }
    end
    return { stamps = out }
end

local function changed()
    serial = serial + 1
    shown_key = nil
end

local function normalize_settings(raw)
    raw = type(raw) == "table" and raw or {}
    local max = tonumber(raw.max)
    max = max and math.floor(max) or M.DEFAULT_MAX
    local cfg = {
        enabled = raw.enabled ~= false,
        max = math.max(0, math.min(M.CAP, max)),
        icons = {},
        by_id = {},
    }
    for _, icon in ipairs(type(raw.icons) == "table" and raw.icons or {}) do
        local id = type(icon) == "table" and text(icon.id)
        if id and not cfg.by_id[id] and text(icon.glyph) then
            local row = { id = id, glyph = icon.glyph, color = icon.color, label = text(icon.label) }
            cfg.icons[#cfg.icons + 1] = row
            cfg.by_id[id] = row
        end
    end
    return cfg
end

-- The world_map section's `stamps` block. RuntimeSettings.section copies
-- every creator override, so it is read once per settings revision (R2 S7).
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if config == nil or config_revision ~= revision then
        local section = Runtime.section("world_map", require "developer.config.world_map_settings") or {}
        config = normalize_settings(section.stamps)
        config_revision = revision
        shown_key = nil
    end
    return config
end

-- Players can place and see stamps: enabled, a limit above zero and an icon.
function M.available()
    local cfg = M.settings()
    return cfg.enabled and cfg.max > 0 and #cfg.icons > 0
end

function M.revision() return serial end
function M.count() return #state.stamps end
function M.list() return copy_state().stamps end

function M.add(icon, room, x, y)
    local cfg = M.settings()
    if not cfg.enabled then return false, "disabled" end
    if not (text(icon) and cfg.by_id[icon]) then return false, "icon" end
    if not text(room) then return false, "room" end
    if not (finite(x) and finite(y)) then return false, "position" end
    if #state.stamps >= cfg.max then return false, "limit" end
    state.stamps[#state.stamps + 1] = { icon = icon, room = room, x = round(x), y = round(y) }
    changed()
    return true
end

function M.remove(index)
    if type(index) ~= "number" or not state.stamps[index] then return false end
    table.remove(state.stamps, index)
    changed()
    return true
end

-- World position of a saved row, or nil while its room is not in the layout
-- (a stamp in a removed room is hidden, not deleted).
function M.world_position(row)
    local Rooms = require "mvtk.map.streaming.room_manager"
    local Geometry = require "mvtk.map.streaming.room_geometry"
    local room = row and Rooms.get_room_data(row.room)
    if not room then return nil end
    local ox, oy = Geometry.compute_spawn_xy(room)
    return ox + row.x, oy + row.y
end

-- A room the map already shows the player: not a hidden secret, and visited
-- or revealed (every room while discovery is off).
function M.room_known(id)
    local Discovery = require "mvtk.map.discovery"
    if not id or Discovery.is_secret_hidden(nil, nil, id) then return false end
    if not Discovery.enabled() then return true end
    return Discovery.is_visited(id) or Discovery.is_revealed(id)
end

local function rect_distance(b, x, y)
    local dx = math.max(b.min_x - x, 0, x - b.max_x)
    local dy = math.max(b.min_y - y, 0, y - b.max_y)
    return dx * dx + dy * dy
end

-- Correction 2: the room a world point belongs to. `room` is the visible room
-- the map found under the point (G8-06's room_at, checked with
-- Discovery.is_visible); when it is nil or a hidden secret, the point attaches
-- to the nearest known room, with room-local coordinates that may lie outside
-- its bounds. So stamps can sit on blank map, and a hidden room is never
-- revealed by refusing a stamp. Returns room, x, y or nil.
function M.attach(wx, wy, room)
    if not (finite(wx) and finite(wy)) then return nil end
    local Rooms = require "mvtk.map.streaming.room_manager"
    local Geometry = require "mvtk.map.streaming.room_geometry"
    local Discovery = require "mvtk.map.discovery"
    if not (room and not Discovery.is_secret_hidden(nil, nil, room) and Rooms.get_room_data(room)) then
        room = nil
        local best
        for _, id in ipairs(Rooms.list_rooms()) do
            local bounds = Rooms.get_room_bounds(id)
            if bounds and M.room_known(id) then
                local d = rect_distance(bounds, wx, wy)
                if best == nil or d < best then best, room = d, id end
            end
        end
        if not room then return nil end
    end
    local ox, oy = Geometry.compute_spawn_xy(Rooms.get_room_data(room))
    return room, round(wx - ox), round(wy - oy)
end

function M.place(icon, wx, wy, room)
    local cfg = M.settings()
    if not cfg.enabled then return false, "disabled" end
    if #state.stamps >= cfg.max then return false, "limit" end
    local id, x, y = M.attach(wx, wy, room)
    if not id then return false, "room" end
    return M.add(icon, id, x, y)
end

-- The stamps to draw: {index, icon, glyph, color, label, x, y (world)}.
-- Hidden: stamps switched off, icons no longer in the palette, rooms not in
-- the layout and positions a hidden secret covers (correction 3). Rebuilt only
-- when stamps, discovery, settings or the session change.
function M.shown()
    local cfg = M.settings()
    if not cfg.enabled or #state.stamps == 0 then return {} end
    local Discovery = require "mvtk.map.discovery"
    local key = serial .. ":" .. tostring(Discovery.revision()) .. ":" .. tostring(config_revision) .. ":" .. session
    if shown_key == key then return shown_list end
    local list = {}
    for index, row in ipairs(state.stamps) do
        local icon = cfg.by_id[row.icon]
        local wx, wy
        if icon then wx, wy = M.world_position(row) end
        if wx and not Discovery.is_secret_hidden(wx, wy, row.room) then
            list[#list + 1] = { index = index, icon = row.icon, glyph = icon.glyph, color = icon.color,
                label = icon.label, room = row.room, x = wx, y = wy }
        end
    end
    shown_key, shown_list = key, list
    return list
end

-- Index of the nearest shown stamp within `radius` world units, or nil.
function M.at(wx, wy, radius)
    local best, index
    local r2 = (tonumber(radius) or 0) ^ 2
    for _, row in ipairs(M.shown()) do
        local d = (row.x - wx) ^ 2 + (row.y - wy) ^ 2
        if d <= r2 and (best == nil or d < best) then best, index = d, row.index end
    end
    return index
end

-- A new session can bring another layout: recompute world positions.
function M.on_session_start()
    session = session + 1
    shown_key = nil
end

Checkpoint.register_provider("map_stamps", {
    version = 1,
    order = 55,
    description = "Player map stamps: palette ids and room-local positions",
    migrations = {},
    capture = function() return copy_state() end,
    apply = function(data) state = sanitize(data); changed() end,
    defaults = function() state = { stamps = {} }; changed() end,
})

return M
