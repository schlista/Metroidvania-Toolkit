-- Map item tracking: which census entries the maps mark, with what icon and style.
-- Pure apart from the census and saved state; the world map and minimap draw it.
-- Station icons persist: once seen, they stay across room unloads and saves until
-- the station is gone for good (STAGE_7 D-S7B-1). Never call this per frame for
-- every entry without the index: M.index() rebuilds only when the census catalog
-- or the room layout changes. Presence, discovery and flags are checked live.
local Census = require "mvtk.world.census"
local Discovery = require "mvtk.map.discovery"
local Flags = require "mvtk.core.flags"
local Gates = require "mvtk.world.gates.gate_manager"
local Rooms = require "mvtk.map.streaming.room_manager"
local Geometry = require "mvtk.map.streaming.room_geometry"
local Util = require "mvtk.core.util"
local M = {}

-- Item tracking (switch, rule, required flag) applies to these kinds only.
M.TRACKED = { item = true, chest = true, lore = true, secret = true }
-- Kinds whose baked show_on_map can turn the icon off.
local SHOW_ON_MAP = { travel = true, shop = true, upgrade_station = true, bank = true,
    skill_trainer = true, offering_altar = true }
-- Registry ids the station and marker scripts use, for de-duplication.
local REGISTRY = {
    fast_travel = function(e) return "fast_travel:" .. e.id end,
    save_point = function(e) return "save_point:" .. tostring(e.room) .. ":" .. e.id end,
    map_marker = function(e) return e.id end,
}
local STATION = { shop = true, upgrade_station = true, bank = true, skill_trainer = true, offering_altar = true }

local cached, cached_revision, world_colors, types
local index, index_catalog, index_layout

function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if not cached or cached_revision ~= revision then
        cached = Runtime.section("map_icons", require "developer.config.map_icons")
        world_colors = (Runtime.section("world_map", require "developer.config.world_map_settings") or {}).colors or {}
        cached_revision = revision
    end
    return cached
end

local function collectible_types()
    types = types or Util.require_config("developer.config.collectible_types", {})
    return types
end

local function text(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

-- A type row (save_point) wins over its kind row (travel).
function M.row(entry)
    local kinds = M.settings().kinds or {}
    return kinds[entry.type] or kinds[entry.kind] or {}
end

-- The icon id: an explicit Tiled map_icon, else an item's minimap_icon.
function M.icon_id(entry)
    local icon = text(entry.map_icon)
    if icon and icon ~= "auto" then return icon end
    if entry.kind == "item" then return (collectible_types()[entry.type] or {}).minimap_icon end
end

-- The id a script registers for this entry in Discovery.markers, if any.
function M.registry_id(entry)
    if STATION[entry.type] then return "station:" .. tostring(entry.room) .. ":" .. entry.id end
    local key = REGISTRY[entry.type]
    return key and key(entry) or nil
end

local function world_position(entry)
    if entry.wx then return entry.wx, entry.wy end
    local x, y = Geometry.compute_spawn_xy(Rooms.get_room_data(entry.room))
    return (x or 0) + (entry.x or 0), (y or 0) + (entry.y or 0)
end

-- Found, taken, opened, defeated or used.
function M.collected(entry)
    if entry.type == "offering_altar" then return Flags.has("altar_used:" .. entry.id) end
    return Census.state(entry) == true
end

-- Gone for good: the object will never come back, so its icon goes too.
function M.gone(entry)
    if Census.present(entry) == false then return true end
    if entry.type == "offering_altar" then
        return entry.remove_after_use == true and Flags.has("altar_used:" .. entry.id)
    elseif entry.type == "skill_trainer" then
        return entry.leave_when_done == true and require("mvtk.economy.catalog").all_abilities_learned({ catalog_id = entry.catalog_id })
    elseif entry.kind == "npc" then
        return text(entry.despawn_flag) ~= nil and Flags.has(text(entry.despawn_flag))
    end
    return false
end

-- Hidden ability markers keep their gate preset's hidden visual off the map.
local function hidden_barrier(entry)
    if entry.hidden == true then return true end
    if entry.type ~= "gate" then return false end
    local preset = Gates.get_gate_type(entry.gate_type) or {}
    return type(preset.visual) == "table" and preset.visual.hidden == true
end

function M.rule_passes(rule, entry)
    local x, y = world_position(entry)
    if rule == "always" then return true
    elseif rule == "never" or type(rule) ~= "string" then return false
    elseif rule == "visited" then return Discovery.is_visited(entry.room)
    elseif rule == "seen" then return Discovery.is_seen(x, y, entry.room)
    elseif rule == "mapped" then return Discovery.is_revealed(entry.room) or Discovery.is_seen(x, y, entry.room) end
    local ability = rule:match("^ability:(.+)$")
    if ability then return require("mvtk.abilities.ability_manager").has_ability(ability) == true end
    local flag = rule:match("^flag:(.+)$")
    if flag then return Flags.has(flag) end
    return false
end

-- True while item tracking may mark items: the switch is on and its required
-- flag, if any, is set. The world map's "items left" dots and lines use it.
function M.tracking_on()
    local tracking = M.settings().item_tracking or {}
    if tracking.enabled == false then return false end
    local required = text(tracking.require_flag)
    return not (required and not Flags.has(required))
end

-- The rule that applies to this entry, after the item tracking switch.
function M.rule(entry)
    local row = M.row(entry)
    if M.TRACKED[entry.kind] then
        local tracking = M.settings().item_tracking or {}
        if tracking.enabled == false then return "never" end
        local required = text(tracking.require_flag)
        if required and not Flags.has(required) then return "never" end
        return row.rule or tracking.rule or "seen"
    end
    return row.rule or "seen"
end

-- surface: optional "minimap" or "world_map", for a placed marker's own switches.
function M.visible(entry, surface)
    if entry.hide_on_map == true or M.icon_id(entry) == "hide" then return false end
    local x, y = world_position(entry)
    if Discovery.is_secret_hidden(x, y, entry.room) or M.gone(entry) then return false end
    if entry.kind == "barrier" and hidden_barrier(entry) then return false end
    if SHOW_ON_MAP[entry.kind] and entry.show_on_map == false then return false end
    local row = M.row(entry)
    if row.hidden_until_found == true and not M.collected(entry) then return false end
    if entry.kind == "map_marker" then
        if surface == "minimap" and entry.show_on_minimap == false then return false end
        if surface == "world_map" and entry.show_on_world_map == false then return false end
        if row.rule == "never" then return false end
        -- Visible from start shows at once; otherwise the registry's discovery decides.
        if entry.visible_from_start ~= true then
            local marker = Discovery.markers[entry.id]
            if not (type(marker) == "table" and marker.discovered == true) then return false end
        end
    elseif not M.rule_passes(M.rule(entry), entry) then
        return false
    end
    return M.style(entry) ~= "hide"
end

-- "normal", or the row's collected style once collected: "hide", "dim" or "outline".
function M.style(entry)
    local style = M.row(entry).collected
    if style and style ~= "normal" and M.collected(entry) then return style end
    return "normal"
end

local function rgba(c)
    -- world_map_settings colours are vector4 values at runtime: read x..w only.
    if type(c) == "userdata" then return c.x, c.y, c.z, c.w end
    if type(c) ~= "table" then return nil end
    local r, g, b, a = c.r or c.x, c.g or c.y, c.b or c.z, c.a or c.w
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b, type(a) == "number" and a or 1
end

-- Converts a {r, g, b, a} table (or a vector4) to a vector4 when vmath exists.
function M.color(c)
    local r, g, b, a = rgba(c)
    if not r then return nil end
    if vmath and vmath.vector4 then return vmath.vector4(r, g, b, a) end
    return { x = r, y = g, z = b, w = a }
end

-- Shape, colour, label and alpha of the entry's icon. The label is source text:
-- the displaying GUI translates it. A station's own name wins over its kind label.
function M.appearance(entry)
    local cfg, row = M.settings(), M.row(entry)
    local icon = (cfg.icons or {})[M.icon_id(entry) or ""] or {}
    local def = entry.kind == "item" and collectible_types()[entry.type] or {}
    local color = M.color(def.minimap_color) or M.color(icon.color) or M.color(row.color)
        or M.color(world_colors[row.color_from or ""]) or M.color({ r = 1, g = 1, b = 1, a = 1 })
    local style = M.style(entry)
    local dim = tonumber(cfg.dim_alpha) or 0.4
    return { shape = icon.shape or row.shape or "square", color = color, style = style,
        alpha = style == "dim" and dim or 1,
        label = text(entry.name) or text(entry.marker_label) or icon.label or row.label or "" }
end

-- Entries with world positions, grouped by room. They depend only on the census
-- catalog and the layout, so revealed cells and flag changes never rebuild them;
-- callers check presence, discovery and state live (visible, goal_target).
function M.invalidate() index, index_catalog, index_layout = nil, nil, nil end
function M.index()
    local catalog, layout = Census.catalog(), Rooms.layout_revision()
    if index and index_catalog == catalog and index_layout == layout then return index end
    local out, origins = { rooms = {}, list = {}, registry = {} }, {}
    for _, entry in ipairs(Census.entries()) do
        local room = entry.room
        local list = out.rooms[room]
        if not list then list = {}; out.rooms[room] = list; list.seen = {} end
        local key = entry.kind .. ":" .. tostring(entry.id)
        if not list.seen[key] then
            list.seen[key] = true
            local origin = origins[room]
            if not origin then
                local x, y = Geometry.compute_spawn_xy(Rooms.get_room_data(room))
                origin = { x or 0, y or 0 }; origins[room] = origin
            end
            local copy = {}
            for k, v in pairs(entry) do copy[k] = v end
            copy.wx, copy.wy = origin[1] + (entry.x or 0), origin[2] + (entry.y or 0)
            list[#list + 1] = copy; out.list[#out.list + 1] = copy
            local registered = M.registry_id(copy)
            if registered then out.registry[registered] = copy end
        end
    end
    for _, list in pairs(out.rooms) do list.seen = nil end
    index, index_catalog, index_layout = out, catalog, layout
    return out
end

-- The current goal's target (G8-13b): its census entry from the index, once a
-- Hint Stone revealed it (goal_revealed_<id>) and while the object is present.
-- Drawn whatever item_tracking says. Returns entry, goal or nil. Presence and
-- concealment are read live: the index does not rebuild on flag changes.
function M.goal_target()
    local Goals = require "mvtk.game.goals"
    local goal = Goals.current()
    local target = goal and goal.target
    if type(target) ~= "table" or not Flags.has("goal_revealed_" .. tostring(goal.id)) then return nil end
    local objective, marker = text(target.objective), text(target.marker)
    if not objective and not marker then return nil end
    for _, entry in ipairs(M.index().list) do
        local hit = (objective and entry.objective == objective)
            or (marker and entry.kind == "map_marker" and entry.id == marker)
        if hit then
            if Census.present(entry) == false then return nil end
            local x, y = world_position(entry)
            if Discovery.is_secret_hidden(x, y, entry.room) then return nil end
            return entry, goal
        end
    end
    return nil
end

-- Registered markers the census does not already list (dedupe by registry id).
function M.extra_markers(registry)
    local covered, out = M.index().registry, {}
    for id, marker in pairs(registry or {}) do
        if not covered[id] then out[#out + 1] = marker end
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

-- Counted items of a room: {found, total, visited, complete}. An unfound secret
-- stays out until found (STAGE_7 D-S7B-6); completion totals do not change.
function M.room_status(room)
    local found, total = 0, 0
    for _, entry in ipairs(M.index().rooms[room] or {}) do
        if Census.counts(entry) then
            local done = Census.state(entry) == true
            if entry.kind ~= "secret" or done then
                total = total + 1
                if done then found = found + 1 end
            end
        end
    end
    local visited = Discovery.is_visited(room)
    return { found = found, total = total, visited = visited,
        complete = visited and total > 0 and found == total }
end

return M
