-- World budget: counts what each baked room puts into the engine's pools and
-- compares the worst streaming neighbourhood with game.project.
-- Pure Lua for the editor (LuaJ) and headless tests: no frontier patterns, no
-- %.Nf formats, integers only in string.format. Reads go through opts.read.
--
-- Pool scope, read from the Defold 1.14.0 engine source (slice a of
-- docs/metroidvania/STAGE_7_WORLD_SCALE_PLAN.md, G8-04 correction 1). Every
-- room spawns through main:/room_factories#room_factory_<id> into the one
-- `main` collection, so each pool below counts the whole resident set,
-- disabled rooms included, except max_tile_count:
--   collection.max_instances      live game objects, enabled or not
--                                 (gameobject.cpp:1134; ceiling 1<<20, :66)
--   sprite.max_count              created sprites (comp_sprite.cpp:754-757)
--   physics.max_collision_object_count  created objects
--                                 (comp_collision_object_box2d.cpp:179, :489-491)
--   tilemap.max_count             created tilemaps (comp_tilegrid.cpp:163, :419-421)
--   tilemap.max_tile_count        PER FRAME: non-empty cells of enabled tilemaps,
--                                 on visible layers, in 32 x 32-cell regions that
--                                 pass frustum culling (comp_tilegrid.cpp:53,
--                                 :152-165, :611-614, :651-687, :797-803). Disabled
--                                 rooms and off-camera regions cost nothing, so it
--                                 is reported as a view estimate, not a sum.
--   particle_fx.max_count         created components (comp_particlefx.cpp:140, :200-203)
--   sound.max_component_count     created components (comp_sound.cpp:96, :131-133)
--   label.max_count               created labels, damage numbers included
--                                 (comp_label.cpp:156, :386-388; default 64)
--   factory.max_count,
--   collectionfactory.max_count   factory components, not spawned objects
--                                 (comp_factory.cpp:135, :167;
--                                 comp_collection_factory.cpp:82, :115)
--   resource.max_resources        every loaded resource, process-wide
--                                 (resource.cpp:818-821, :1031-1034)
-- Defaults when game.project omits a key come from Bob's meta.properties at
-- the 1.14.0 tag.
local Resource = require "mvtk.editor.resource_text"
local Project = require "developer.tools.relationship_project"
local M = {VERSION = 1}

M.CACHE_PATH = "assets/tiled/world_budget.lua"
M.REPORT_PATH = "developer/assets/tiled/world_budget.txt"
M.REGION = 32 -- comp_tilegrid.cpp:53, cells per render region side
M.BASELINE_PATHS = {"/developer/game/main.collection",
    "/developer/game/player/player_sprite_factory.collectionfactory"}
M.ELEVATOR_DIR = "developer/rooms/collections/_mvtk_elevators"

M.POOLS = {
    {key="instances", section="collection", name="max_instances", default=1024, label="game objects"},
    {key="sprite", section="sprite", name="max_count", default=128, label="sprites"},
    {key="collision", section="physics", name="max_collision_object_count", default=128, label="collision objects"},
    {key="tilemap", section="tilemap", name="max_count", default=16, label="tilemaps"},
    {key="tiles", section="tilemap", name="max_tile_count", default=2048, label="tiles in view (estimate)", view=true},
    {key="particlefx", section="particle_fx", name="max_count", default=64, label="particle effects"},
    {key="sound", section="sound", name="max_component_count", default=32, label="sound components"},
    {key="label", section="label", name="max_count", default=64, label="labels"},
    {key="factory", section="factory", name="max_count", default=128, label="factories"},
    {key="collectionfactory", section="collectionfactory", name="max_count", default=128, label="collection factories"},
    {key="resources", section="resource", name="max_resources", default=1024, label="resources (estimate)", world=true},
}

-- Component file extension or embedded type -> pool key.
local COMPONENT_POOLS = {sprite="sprite", collisionobject="collision", tilemap="tilemap",
    particlefx="particlefx", sound="sound", label="label", factory="factory",
    collectionfactory="collectionfactory"}

-- What one runtime-spawned object of each reserve kind costs.
M.RESERVE_COSTS = {
    projectile={instances=1, sprite=1, collision=1},
    damage_number={instances=1, label=1},
    enemies={instances=1, sprite=1, collision=1},
    pickups={instances=1, sprite=1, collision=1},
}

local function new_counts()
    local c = {}
    for _, pool in ipairs(M.POOLS) do c[pool.key] = 0 end
    return c
end
local function add_counts(into, from, times)
    for key, value in pairs(from) do
        if type(value) == "number" then into[key] = (into[key] or 0) + value * (times or 1) end
    end
end
local function int(value) return math.floor((tonumber(value) or 0) + 0.5) end

---------------------------------------------------------------------------
-- game.project
---------------------------------------------------------------------------
function M.parse_project(text)
    local out, section = {}, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        local name = line:match("^%s*%[([^%]]+)%]%s*$")
        if name then section = name; out[section] = out[section] or {}
        elseif section then
            local key, value = line:match("^%s*([%w_%.#]+)%s*=%s*(.-)%s*$")
            if key then out[section][key] = value end
        end
    end
    return out
end

function M.limits(project)
    local out = {}
    for _, pool in ipairs(M.POOLS) do
        local value = tonumber(((project or {})[pool.section] or {})[pool.name])
        out[pool.key] = value and int(value) or pool.default
    end
    return out
end

---------------------------------------------------------------------------
-- Resource parsing (by meaning; never byte comparisons)
---------------------------------------------------------------------------
-- Painted cells of one .tilemap on visible layers, bucketed into 32 x 32
-- regions anchored at the tilemap's minimum cell (comp_tilegrid.cpp:594-597).
-- tile: 0 is a real tile; only absent cells are empty. A layer is skipped
-- only when it is baked with is_visible: 0 (tag layers such as grapple and
-- ice are baked that way).
function M.count_tilemap(text)
    local cells, min_x, min_y, max_x, max_y = {}, nil, nil, nil, nil
    local root = Resource.parse(text or "").root
    for _, layer in ipairs(Resource.all(root, "layers")) do
        local visible = tonumber(Resource.value(layer.node, "is_visible"))
        if visible ~= 0 then
            for _, cell in ipairs(Resource.all(layer.node, "cell")) do
                local x = tonumber(Resource.value(cell.node, "x")) or 0
                local y = tonumber(Resource.value(cell.node, "y")) or 0
                cells[#cells+1] = x; cells[#cells+1] = y
                min_x = min_x and math.min(min_x, x) or x; min_y = min_y and math.min(min_y, y) or y
                max_x = max_x and math.max(max_x, x) or x; max_y = max_y and math.max(max_y, y) or y
            end
        end
    end
    local buckets, count = {}, #cells / 2
    -- Anchor at the minimum painted cell of the visible layers.
    for i = 1, #cells, 2 do
        local key = math.floor((cells[i] - min_x) / M.REGION) .. "," .. math.floor((cells[i+1] - min_y) / M.REGION)
        buckets[key] = (buckets[key] or 0) + 1
    end
    return {cells=count, buckets=buckets,
        width=min_x and (max_x - min_x + 1) or 0, height=min_y and (max_y - min_y + 1) or 0}
end

local function extension(path) return tostring(path or ""):match("%.([%w_]+)$") end

-- ctx (M.context): read(path) -> text, memo (parsed results shared for one
-- run), files (per memo key, every file that result read) and frames (the
-- open file sets: a room's dependency list and any memo being computed).
local count_go, count_collection
local function memoized(ctx, key, compute)
    if ctx.memo[key] == nil then
        local frame = {}
        ctx.frames[#ctx.frames+1] = frame
        local value = compute()
        table.remove(ctx.frames)
        ctx.memo[key], ctx.files[key] = value, frame
        for path in pairs(frame) do
            for _, open in ipairs(ctx.frames) do open[path] = true end
        end
    else
        for path in pairs(ctx.files[key]) do
            for _, open in ipairs(ctx.frames) do open[path] = true end
        end
    end
    return ctx.memo[key]
end

local function component(ctx, out, kind, path)
    local pool = COMPONENT_POOLS[kind or ""]
    if pool then out.counts[pool] = out.counts[pool] + 1 end
    if kind == "tilemap" and path then
        local tm = memoized(ctx, "tilemap:" .. path, function()
            local text = ctx.read(path)
            return text and M.count_tilemap(text) or false
        end)
        if tm then out.tilemaps[#out.tilemaps+1] = tm end
    elseif path then
        -- Other component files are loaded resources but add no counts.
        memoized(ctx, "file:" .. path, function() ctx.read(path); return true end)
    end
end

local function merge_result(into, from)
    add_counts(into.counts, from.counts)
    for _, tm in ipairs(from.tilemaps) do into.tilemaps[#into.tilemaps+1] = tm end
end
local function empty_result() return {counts=new_counts(), tilemaps={}} end

-- Components of one game object (.go text or an embedded instance's data).
function count_go(ctx, text)
    local out = empty_result()
    local root = Resource.parse(text or "").root
    for _, entry in ipairs(Resource.all(root, "components")) do
        local path = Resource.value(entry.node, "component")
        component(ctx, out, extension(path), path)
    end
    for _, entry in ipairs(Resource.all(root, "embedded_components")) do
        component(ctx, out, Resource.value(entry.node, "type"), nil)
    end
    return out
end

local function prototype(ctx, path)
    return memoized(ctx, "go:" .. path, function()
        local text = ctx.read(path)
        return text and count_go(ctx, text) or empty_result()
    end)
end

-- One game object per instance, embedded instance and nested collection member.
function count_collection(ctx, text, depth)
    assert((depth or 0) < 16, "Collections nest too deeply")
    local out = empty_result()
    local root = Resource.parse(text or "").root
    for _, entry in ipairs(Resource.all(root, "instances")) do
        out.counts.instances = out.counts.instances + 1
        local path = Resource.value(entry.node, "prototype")
        if path then merge_result(out, prototype(ctx, path)) end
    end
    for _, entry in ipairs(Resource.all(root, "embedded_instances")) do
        out.counts.instances = out.counts.instances + 1
        merge_result(out, count_go(ctx, Resource.value(entry.node, "data") or ""))
    end
    for _, entry in ipairs(Resource.all(root, "collection_instances")) do
        local path = Resource.value(entry.node, "collection")
        if path then
            merge_result(out, memoized(ctx, "collection:" .. path, function()
                local nested = ctx.read(path)
                return nested and count_collection(ctx, nested, (depth or 0) + 1) or empty_result()
            end))
        end
    end
    return out
end
M.count_go = function(text, ctx) return count_go(ctx or M.context(function() end), text) end
M.count_collection = function(text, ctx) return count_collection(ctx or M.context(function() end), text, 0) end

-- Combine a room's tilemaps into one region histogram. Each tilemap keeps its
-- own anchor; the extra region in the view window absorbs the misalignment.
local function room_histogram(tilemaps)
    local buckets, cells, width, height = {}, 0, 0, 0
    for _, tm in ipairs(tilemaps) do
        cells = cells + tm.cells
        width, height = math.max(width, tm.width), math.max(height, tm.height)
        for key, n in pairs(tm.buckets) do buckets[key] = (buckets[key] or 0) + n end
    end
    return buckets, cells, width, height
end

-- Largest number of painted cells that one view window can cover.
function M.view_max(buckets, window_x, window_y)
    local list, best = {}, 0
    for key, n in pairs(buckets or {}) do
        local x, y = key:match("^(-?%d+),(-?%d+)$")
        list[#list+1] = {x=tonumber(x), y=tonumber(y), n=n}
    end
    -- Some best window has a populated column on its left edge and a
    -- populated row on its top edge, so only those origins need trying.
    local xs, ys, seen_x, seen_y = {}, {}, {}, {}
    for _, r in ipairs(list) do
        if not seen_x[r.x] then seen_x[r.x] = true; xs[#xs+1] = r.x end
        if not seen_y[r.y] then seen_y[r.y] = true; ys[#ys+1] = r.y end
    end
    for _, x0 in ipairs(xs) do
        for _, y0 in ipairs(ys) do
            local sum = 0
            for _, r in ipairs(list) do
                if r.x >= x0 and r.x < x0 + window_x and r.y >= y0 and r.y < y0 + window_y then sum = sum + r.n end
            end
            if sum > best then best = sum end
        end
    end
    return best
end

-- View window in regions: the design picture widened to display max_aspect,
-- divided by the default camera zoom and tile size. Zones that zoom further
-- out are not modelled.
function M.view_window(view)
    local w, h = tonumber(view.width) or 1920, tonumber(view.height) or 1080
    if view.mode ~= "letterbox" then w = math.max(w, h * (tonumber(view.max_aspect) or 1)) end
    local zoom = tonumber(view.zoom) or 1
    if zoom <= 0 then zoom = 1 end
    local tw, th = tonumber(view.tile_w) or 64, tonumber(view.tile_h) or tonumber(view.tile_w) or 64
    local tiles_x, tiles_y = math.ceil(w / zoom / tw), math.ceil(h / zoom / th)
    return math.ceil(tiles_x / M.REGION) + 1, math.ceil(tiles_y / M.REGION) + 1, tiles_x, tiles_y
end

function M.context(read)
    local ctx = {memo={}, files={}, frames={}}
    ctx.read = function(path)
        local text = read(path)
        for _, open in ipairs(ctx.frames) do open[path] = true end
        return text
    end
    return ctx
end

---------------------------------------------------------------------------
-- Neighbourhoods
---------------------------------------------------------------------------
local function graph_of(layout, room_ids)
    local graph = {}
    for _, id in ipairs(room_ids) do graph[id] = {} end
    for _, record in ipairs((layout and layout.rooms) or {}) do
        local id = record.id
        if graph[id] then
            for _, n in ipairs(record.neighbors or {}) do
                local other = type(n) == "table" and n.id or n
                if graph[other] and other ~= id then graph[id][other] = true; graph[other][id] = true end
            end
        end
    end
    local out = {}
    for id, set in pairs(graph) do
        local list = {}
        for other in pairs(set) do list[#list+1] = other end
        table.sort(list); out[id] = list
    end
    return out
end

local function within(graph, start, hops)
    local dist, queue, head = {[start]=0}, {start}, 1
    while queue[head] do
        local id = queue[head]; head = head + 1
        if dist[id] < hops then
            for _, n in ipairs(graph[id] or {}) do
                if dist[n] == nil then dist[n] = dist[id] + 1; queue[#queue+1] = n end
            end
        end
    end
    return dist
end

local function radius_of(stream)
    local room = stream or {}
    local r = tonumber(room.preload_distance)
    if r == nil then r = math.max(tonumber(room.preload_x) or 1, tonumber(room.preload_y) or 1) end
    return math.max(1, math.floor(r))
end

-- Resident set of the room manager around `id` (correction 3): the visible
-- set (room plus preload radius; direct neighbours always), plus the largest
-- neighbour's visible set when lookahead is on, plus the inactive_room_cache
-- largest rooms within two more hops. keep_all_loaded keeps the whole world.
-- Returns, per pool, the worst total and the rooms that made it.
function M.resident(graph, counts, id, stream, pool_key)
    stream = stream or {}
    local all = {}
    if stream.keep_all_loaded == true then
        local total, rooms = 0, {}
        for room, c in pairs(counts) do total = total + (c[pool_key] or 0); rooms[#rooms+1] = room end
        table.sort(rooms)
        return total, rooms
    end
    local radius = radius_of(stream)
    local base = within(graph, id, radius)
    local best_set = base
    if (tonumber(stream.lookahead_tiles) or 0) > 0 then
        local best = -1
        for _, n in ipairs(graph[id] or {}) do
            local set = {}
            for room in pairs(base) do set[room] = true end
            for room in pairs(within(graph, n, radius)) do set[room] = true end
            local sum = 0
            for room in pairs(set) do sum = sum + ((counts[room] or {})[pool_key] or 0) end
            if sum > best then best = sum; best_set = set end
        end
    end
    for room in pairs(best_set) do all[room] = true end
    local reach = radius + ((tonumber(stream.lookahead_tiles) or 0) > 0 and 1 or 0) + 2
    local cached = {}
    for room in pairs(within(graph, id, reach)) do
        if not all[room] then cached[#cached+1] = room end
    end
    table.sort(cached, function(a, b)
        local ca, cb = (counts[a] or {})[pool_key] or 0, (counts[b] or {})[pool_key] or 0
        if ca ~= cb then return ca > cb end
        return a < b
    end)
    for i = 1, math.min(#cached, math.max(0, math.floor(tonumber(stream.inactive_room_cache) or 0))) do
        all[cached[i]] = true
    end
    local total, rooms = 0, {}
    for room in pairs(all) do total = total + ((counts[room] or {})[pool_key] or 0); rooms[#rooms+1] = room end
    table.sort(rooms)
    return total, rooms
end

---------------------------------------------------------------------------
-- Check (the Prepare & Check stage)
---------------------------------------------------------------------------
local function resource_path(root, path)
    if path:sub(1, 1) == "/" then return root .. path end
    return root .. "/" .. path
end

local function fresh_loader(opts, root, read)
    return require("mvtk.editor.fresh_config").new({root=root, read=function(path) return read(path) end})
end

local function load_config(loader, path)
    local value = loader.load_path(path)
    return type(value) == "table" and value or {}
end

local function room_ids_of(opts, layout, root)
    local ids, seen = {}, {}
    for _, record in ipairs((layout and layout.rooms) or {}) do
        if type(record.id) == "string" and not seen[record.id] then seen[record.id] = true; ids[#ids+1] = record.id end
    end
    if #ids == 0 and opts.list_dir_filesystem then
        local _, files = opts.list_dir_filesystem(root .. "/developer/assets/tiled/maps")
        for _, name in ipairs(files or {}) do
            local id = name:match("^(.+)%.lua$")
            if id and not seen[id] then seen[id] = true; ids[#ids+1] = id end
        end
    end
    table.sort(ids)
    return ids
end

-- One run reads each file once and fingerprints it once (correction 9).
local function run_reader(root, read)
    local texts, prints = {}, {}
    local reader = {}
    function reader.text(path)
        if texts[path] == nil then texts[path] = read(resource_path(root, path)) or false end
        return texts[path] or nil
    end
    function reader.fingerprint(path)
        if prints[path] == nil then
            local text = reader.text(path)
            prints[path] = text and require("developer.tools.preparation").content_fingerprint(path, text) or "missing"
        end
        return prints[path]
    end
    return reader
end

-- A cached room is reused only when every file it read (its collection, each
-- prototype, nested collection, tilemap and component file) is unchanged, and
-- the module version matches.
local function room_entry(reader, ctx, id, cache_rooms)
    local collection = "/developer/rooms/collections/" .. id .. ".collection"
    local old = cache_rooms and cache_rooms[id]
    if old and old.version == M.VERSION and type(old.deps) == "table" and next(old.deps) then
        local fresh = true
        for path, fp in pairs(old.deps) do
            if reader.fingerprint(path) ~= fp then fresh = false; break end
        end
        if fresh then return old, true end
    end
    local frame = {}
    ctx.frames[#ctx.frames+1] = frame
    local text = ctx.read(collection)
    local result = text and count_collection(ctx, text, 0)
    table.remove(ctx.frames)
    if not result then return nil end
    local buckets, cells, width, height = room_histogram(result.tilemaps)
    result.counts.tiles = cells
    -- deps lists every file the room read, which is also its resource estimate.
    local deps = {}
    for path in pairs(frame) do deps[path] = reader.fingerprint(path) end
    return {version=M.VERSION, deps=deps, counts=result.counts, buckets=buckets,
        width=width, height=height}, false
end

-- developer/game/main.collection, the sprite player collection and the
-- persistent world-owned elevator collections (correction 4).
local function baseline_counts(root, ctx, opts, overrides)
    local frame = {}
    ctx.frames[#ctx.frames+1] = frame
    local out = empty_result()
    local main = ctx.read(M.BASELINE_PATHS[1])
    if main then merge_result(out, count_collection(ctx, main, 0)) end
    local factory = ctx.read(M.BASELINE_PATHS[2])
    local player = factory and Resource.value(Resource.parse(factory).root, "prototype")
    local player_text = player and ctx.read(player)
    if player_text then merge_result(out, count_collection(ctx, player_text, 0)) end
    if opts.list_dir_filesystem then
        local _, files = opts.list_dir_filesystem(root .. "/" .. M.ELEVATOR_DIR)
        files = files or {}
        table.sort(files)
        for _, name in ipairs(files) do
            if name:match("%.collection$") then
                local text = ctx.read("/" .. M.ELEVATOR_DIR .. "/" .. name)
                if text then merge_result(out, count_collection(ctx, text, 0)) end
            end
        end
    end
    table.remove(ctx.frames)
    out.counts.tiles = 0
    local paths = 0
    for _ in pairs(frame) do paths = paths + 1 end
    out.counts.resources = paths
    for key, value in pairs(overrides or {}) do
        if out.counts[key] ~= nil and tonumber(value) then out.counts[key] = int(value) end
    end
    return out.counts
end

local function reserve_counts(budgets)
    local out = new_counts()
    local caps, reserve = budgets.spawn_caps or {}, budgets.reserve or {}
    for kind, cost in pairs(M.RESERVE_COSTS) do
        local n = tonumber(caps[kind]) or tonumber(reserve[kind]) or 0
        add_counts(out, cost, math.max(0, int(n)))
    end
    return out
end

-- Approximate save size: flags for persistent ids in the census, packed
-- discovery rows per room and saved screenshot markers. sys.save fails above
-- 512 KB or 65,536 rows in one table (https://defold.com/llms/apis/sys-lua.md),
-- and checkpoint.lua catches that failure, so saves would silently stop.
function M.save_estimate(census, rooms, budgets, cell_tiles)
    local est = budgets.save_estimate or {}
    local per_flag = tonumber(est.bytes_per_flag) or 48
    local flags = 0
    for _, entries in pairs((census and census.rooms) or {}) do flags = flags + #entries end
    local bytes, rows = flags * per_flag, flags
    cell_tiles = math.max(1, cell_tiles or 2)
    for _, entry in pairs(rooms) do
        local discovery_rows = math.ceil((entry.height or 0) / cell_tiles)
        local row_bytes = math.ceil((entry.width or 0) / cell_tiles / 8) + 16
        bytes = bytes + discovery_rows * row_bytes + 32
        rows = math.max(rows, discovery_rows)
    end
    local markers = math.max(0, int(est.screenshot_markers or 0))
    bytes = bytes + markers * math.max(0, int(est.screenshot_marker_bytes or 0))
    return int(bytes), rows
end

local function write_text(opts, path, text)
    if (opts.read or Project.read)(path) == text then return end
    if opts.write then return opts.write(path, text) end
    require("developer.tools.dev_helpers").ensure_dir(path:match("^(.*)/[^/]+$"))
    local f = assert(io.open(path, "wb")); f:write(text); f:close()
end

local function pct(value, limit)
    if limit <= 0 then return 0 end
    return math.floor(value * 100 / limit + 0.5)
end

-- opts: root, read, write, list_dir_filesystem, layout (optional).
-- Returns {lines, errors, summary}. Findings are warnings unless
-- performance_budgets.block_on_overflow is true.
function M.check(opts)
    opts = opts or {}
    local root = tostring(opts.root or "."):gsub("\\", "/"):gsub("/$", "")
    local read = opts.read or Project.read
    local loader = fresh_loader(opts, root, read)
    local budgets = load_config(loader, "developer/config/performance_budgets.lua")
    local stream_cfg = load_config(loader, "developer/config/stream_settings.lua")
    local stream = stream_cfg.room or {}
    local tile = load_config(loader, "developer/config/tile_settings.lua")
    local display = load_config(loader, "developer/config/display_settings.lua")
    local game = load_config(loader, "developer/config/game_config.lua")
    local creator = load_config(loader, "developer/config/creator_settings.lua")
    local overrides = creator.published == true and creator.overrides or {}
    local stream_over = type(overrides.stream_settings) == "table" and overrides.stream_settings.room or nil
    if type(stream_over) == "table" then
        -- Game Settings overrides win, as RuntimeSettings.section merges them in game.
        local merged = {}
        for k, v in pairs(stream) do merged[k] = v end
        for k, v in pairs(stream_over) do merged[k] = v end
        stream = merged
    end
    local caps_over = type(overrides.performance_budgets) == "table" and overrides.performance_budgets.spawn_caps or nil
    if type(caps_over) == "table" then
        -- Game > Large worlds live caps: the reserve follows the game's caps.
        local caps = {}
        for k, v in pairs(type(budgets.spawn_caps) == "table" and budgets.spawn_caps or {}) do caps[k] = v end
        for k, v in pairs(caps_over) do caps[k] = v end
        local merged = {}
        for k, v in pairs(budgets) do merged[k] = v end
        merged.spawn_caps = caps
        budgets = merged
    end
    local view_cfg = ((overrides.display or {}).view) or {}
    local base_view = display.view or {}
    local camera = overrides.camera or {}
    local project = M.parse_project(read(root .. "/game.project"))
    local limits = M.limits(project)
    local layout = opts.layout
    local layout_note
    if not layout then
        layout = Project.load_table(read(root .. "/developer/runtime/layout/world_layout.local.lua"), "world_layout.local.lua")
    end
    if not (layout and type(layout.rooms) == "table" and #layout.rooms > 0) then
        layout = nil
        layout_note = "Export the layout, then Prepare & Check again."
    end

    local cache = Project.load_table(read(root .. "/developer/" .. M.CACHE_PATH), M.CACHE_PATH) or {}
    if cache.version ~= M.VERSION then cache = {} end
    local ids = room_ids_of(opts, layout, root)
    local reader = run_reader(root, read)
    local ctx = M.context(reader.text)
    local rooms, counts, reused, missing = {}, {}, 0, {}
    for _, id in ipairs(ids) do
        local entry, was_cached = room_entry(reader, ctx, id, cache.rooms)
        if entry then
            rooms[id] = entry; counts[id] = entry.counts
            if was_cached then reused = reused + 1 end
        else missing[#missing+1] = id end
    end

    local display_project = project.display or {}
    local wx, wy, tiles_x, tiles_y = M.view_window({
        width=display_project.width, height=display_project.height,
        mode=view_cfg.mode or base_view.mode, max_aspect=view_cfg.max_aspect or base_view.max_aspect,
        zoom=camera.default_zoom or (game.camera or {}).default_zoom,
        tile_w=tile.width, tile_h=tile.height})
    local view = {}
    for id, entry in pairs(rooms) do view[id] = M.view_max(entry.buckets, wx, wy) end

    local graph = graph_of(layout, ids)
    local baseline = baseline_counts(root, ctx, opts, budgets.baseline)
    local reserve = reserve_counts(budgets)
    local all_paths = {}
    for _, entry in pairs(rooms) do for p, fp in pairs(entry.deps or {}) do if fp ~= "missing" then all_paths[p] = true end end end
    local resource_total = 0
    for _ in pairs(all_paths) do resource_total = resource_total + 1 end

    local results = {}
    for _, pool in ipairs(M.POOLS) do
        local worst = {total=0, rooms={}, center=nil}
        if pool.view then
            for _, id in ipairs(ids) do
                if view[id] then
                    local seam, partner = view[id], nil
                    if layout then
                        for _, n in ipairs(graph[id] or {}) do
                            if view[n] and (not partner or view[n] > view[partner]) then partner = n end
                        end
                        if partner then seam = seam + view[partner] end
                    end
                    -- A seam pairs two rooms; name the denser one as its centre.
                    if not worst.center or seam > worst.total or (seam == worst.total and view[id] > view[worst.center]) then
                        worst = {total=seam, center=id, rooms=partner and {id, partner} or {id}}
                    end
                end
            end
        elseif pool.world then
            -- Only scope "all" holds every room's resources at once; region
            -- warming (CP04c) holds a few regions, and "none" holds nothing extra.
            if stream.prewarm_resources_on_start ~= false
                and stream.prewarm_scope ~= "region" and stream.prewarm_scope ~= "none" then
                worst = {total=resource_total, rooms={}, center=nil, world=true}
            end
        else
            for _, id in ipairs(ids) do
                if counts[id] then
                    local total, set
                    if layout then total, set = M.resident(graph, counts, id, stream, pool.key)
                    else total, set = counts[id][pool.key] or 0, {id} end
                    if total > worst.total or not worst.center then worst = {total=total, center=id, rooms=set} end
                end
            end
        end
        local extra = pool.view and 0 or ((baseline[pool.key] or 0) + (reserve[pool.key] or 0))
        local total = worst.total + extra
        local densest
        for _, id in ipairs(worst.rooms or {}) do
            local value = pool.view and view[id] or (counts[id] or {})[pool.key] or 0
            local best = densest and (pool.view and view[densest] or (counts[densest] or {})[pool.key] or 0)
            if not densest or value > best then densest = id end
        end
        results[#results+1] = {pool=pool, total=total, rooms_total=worst.total, extra=extra,
            limit=limits[pool.key], center=worst.center, rooms=worst.rooms or {}, densest=densest}
    end

    local margins = budgets.margins or {}
    local overflows, report, findings = {}, {}, {}
    report[#report+1] = "World budget report. Generated by Project > Prepare & Check; do not edit."
    -- The file holds content only: a run statistic here would rewrite it on every unchanged
    -- Prepare. How many rooms the cache reused goes to the returned log lines instead.
    report[#report+1] = string.format("%d rooms counted.", #ids - #missing)
    for _, id in ipairs(missing) do report[#report+1] = "Not baked yet, skipped: " .. id end
    if layout_note then report[#report+1] = "No exported layout: per-room totals only. " .. layout_note end
    report[#report+1] = string.format("View estimate window: %d x %d tiles (%d x %d regions of 32 tiles).", tiles_x, tiles_y, wx, wy)
    report[#report+1] = ""
    report[#report+1] = "Pool | worst | limit | use | worst neighbourhood"
    for _, r in ipairs(results) do
        local where = r.center and (r.center .. " (" .. #r.rooms .. " rooms)") or (r.pool.world and "all rooms (startup warming)") or "-"
        report[#report+1] = string.format("%s.%s | %d | %d | %d%% | %s", r.pool.section, r.pool.name,
            int(r.total), int(r.limit), pct(r.total, r.limit), where)
        if r.total > r.limit then
            local margin = tonumber(margins[r.pool.section .. "." .. r.pool.name]) or tonumber(margins.default) or 1.25
            overflows[#overflows+1] = {section=r.pool.section, key=r.pool.name, current=int(r.limit),
                worst=int(r.total), margin=margin}
            local remedy
            if r.pool.view then
                remedy = "Split " .. tostring(r.densest) .. " or move scenery to image layers. This is an estimate: camera zones that zoom out further are not modelled."
            elseif r.pool.world then
                remedy = "Set prewarm_scope = \"region\" (or prewarm_resources_on_start = false) in stream_settings.lua, or raise resource.max_resources."
            else
                remedy = "Split " .. tostring(r.densest) .. ", move scenery to tile or image layers, or lower inactive_room_cache in stream_settings.lua."
            end
            local text = string.format("Over the limit: %s.%s needs %d of %d %s around %s (rooms: %s). Densest room: %s. %s",
                r.pool.section, r.pool.name, int(r.total), int(r.limit), r.pool.label, tostring(r.center or "the world"),
                table.concat(r.rooms, ", "), tostring(r.densest or "-"), remedy)
            findings[#findings+1] = text
        end
    end
    report[#report+1] = "Totals include the main collection baseline and the runtime reserve from performance_budgets.lua."

    -- Generated-file census (CP05a): the same run reader, so no file is read twice.
    local generated
    if opts.list_dir_filesystem then
        local Census = require "developer.tools.generated_census"
        generated = Census.count({read=reader.text, dir=stream_cfg.generated_rooms_dir,
            list=function(dir) local _, files = opts.list_dir_filesystem(root .. dir); return files end})
        report[#report+1] = Census.line(generated) .. " By kind: " .. Census.kind_text(generated) .. "."
        generated = {line=Census.line(generated), files=generated.files, unused=generated.unused,
            kinds=generated.kinds, unused_kinds=generated.unused_kinds}
    end

    local slow = tonumber(budgets.slow_room_instances) or 1500
    local slow_rooms = {}
    for _, id in ipairs(ids) do
        if counts[id] and counts[id].instances > slow then
            slow_rooms[#slow_rooms+1] = id
            findings[#findings+1] = string.format("Slow to stream in: %s has %d game objects (threshold %d) and may pause the game while it is created. Split it or move scenery to tile or image layers.",
                id, int(counts[id].instances), int(slow))
        end
    end

    local census = Project.load_table(read(root .. "/developer/config/world_census_generated.lua"), "world_census_generated.lua")
    local save_bytes, save_rows = M.save_estimate(census, rooms, budgets, 2)
    report[#report+1] = string.format("Save size estimate: about %d KB of 512 KB; largest table about %d of 65536 rows.",
        int(save_bytes / 1024), int(save_rows))
    if save_bytes > 512 * 1024 or save_rows > 65536 then
        findings[#findings+1] = "Save size estimate is over sys.save's limit (512 KB or 65,536 rows in one table). Saves would stop working: reduce saved objects or rooms."
    end

    report[#report+1] = ""
    if #findings == 0 then report[#report+1] = "No findings: every pool fits." end
    for _, line in ipairs(findings) do report[#report+1] = line end

    local block = budgets.block_on_overflow == true
    local errors = block and (#overflows + (save_bytes > 512 * 1024 and 1 or 0)) or 0
    local summary = {version=M.VERSION, overflows=overflows, slow_rooms=slow_rooms, findings=#findings, lines={}}
    if #findings == 0 then
        summary.lines[1] = string.format("World budget: every engine pool fits (%d rooms).", #ids - #missing)
    else
        summary.lines[1] = string.format("World budget: %d finding(s); see developer/assets/tiled/world_budget.txt.", #findings)
        for i = 1, math.min(3, #findings) do summary.lines[#summary.lines+1] = findings[i] end
    end
    if generated then
        summary.generated = generated
        table.insert(summary.lines, 2, generated.line)
    end
    if layout_note then summary.lines[#summary.lines+1] = "World budget: " .. layout_note end

    local text = table.concat(report, "\n") .. "\n"
    write_text(opts, root .. "/" .. M.REPORT_PATH, text)
    require("developer.tools.preparation").write_report({root=root, read=opts.read, write=opts.write},
        M.CACHE_PATH, {version=M.VERSION, rooms=rooms, summary=summary})
    local lines = {}
    for _, line in ipairs(summary.lines) do lines[#lines+1] = line end
    -- After the summary and census lines (Preparation Status reads the census as line 2), and before a
    -- closing "Export the layout" note, which stays last.
    local reuse = string.format("World budget: %d rooms counted, %d unchanged since the last run.",
        #ids - #missing, reused)
    if layout_note then table.insert(lines, #lines, reuse) else lines[#lines + 1] = reuse end
    return {lines=lines, errors=errors, summary=summary, findings=findings, report=text}
end

return M
