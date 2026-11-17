-- Resource-only startup warming. Baked room collections still instantiate via
-- the ordinary streamer. Unvisited resources retain a lease until first use;
-- then the ordinary bounded resource cache owns their lifetime.
--
-- Scope (stream_settings.room, CP04c):
--   "all"    warm every published room (the default, and the behaviour with no opts)
--   "region" warm the current room's region plus prewarm_adjacent_regions
--            regions out, by door connections; retarget() follows the player
--   "none"   no warming; prewarm_resources_on_start = false also means none
-- A room with no region joins one shared group, so a world with no regions
-- set warms exactly what "all" warms.
local M = {}

local NO_REGION = {}  -- shared group key for rooms without a region
local MAX_ADJACENT = 4

-- Console report: one line when the first pass finishes and one per region change, so a creator
-- can see which rooms the scope covers. Tests replace M.log.
M.log = print

-- Effective scope for a stream_settings.room table.
function M.scope(room_settings)
    if type(room_settings) ~= "table" or not room_settings.prewarm_resources_on_start then
        return "none"
    end
    local scope = room_settings.prewarm_scope
    if scope == "region" or scope == "none" then return scope end
    return "all"
end

-- prewarm_adjacent_regions clamped to 0..4 (default 1).
function M.adjacent(room_settings)
    local n = tonumber(type(room_settings) == "table" and room_settings.prewarm_adjacent_regions or nil)
    if n == nil then return 1 end
    return math.max(0, math.min(MAX_ADJACENT, math.floor(n)))
end

local function sorted_ids(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- Region of every room, computed once, and region adjacency from door edges.
local function build_regions(rooms, opts)
    local region_of, adjacency = {}, {}
    for id in pairs(rooms) do
        local region = opts.region_of and opts.region_of(id, rooms[id]) or nil
        if region == nil or region == "" then region = NO_REGION end
        region_of[id] = region
        adjacency[region] = adjacency[region] or {}
    end
    local graph = opts.graph or {}
    for id, region in pairs(region_of) do
        for _, edge in ipairs(graph[id] or {}) do
            local other = edge and region_of[edge.id]
            if other and other ~= region then
                adjacency[region][other] = true
                adjacency[other][region] = true
            end
        end
    end
    return region_of, adjacency
end

-- Region-graph distance from `start` to every reachable region.
local function region_distances(adjacency, start)
    local dist = { [start] = 0 }
    local frontier = { start }
    local head = 1
    while frontier[head] do
        local region = frontier[head]
        head = head + 1
        for other in pairs(adjacency[region] or {}) do
            if dist[other] == nil then
                dist[other] = dist[region] + 1
                frontier[#frontier + 1] = other
            end
        end
    end
    return dist
end

function M.new(resources, rooms, factory_url, opts)
    local queue, retained, claimed = {}, {}, {}
    local index, active, active_id = 1, nil, nil
    local first_pass_done = false
    local service = {}

    -- Region scope state; nil for "all".
    local region_of, adjacency, dist, center_region, pending
    local adjacent = 0
    if type(opts) == "table" and opts.scope == "region" then
        adjacent = M.adjacent({ prewarm_adjacent_regions = opts.adjacent })
        region_of, adjacency = build_regions(rooms, opts)
        pending = {}
    end

    local function wanted(id)
        if not region_of then return true end
        local d = dist and dist[region_of[id]]
        return d ~= nil and d <= adjacent
    end

    local function far(id)
        if not region_of then return false end
        local d = dist and dist[region_of[id]]
        return d == nil or d > adjacent + 1
    end

    local total = 0
    for _ in pairs(rooms) do total = total + 1 end

    local function region_name(region)
        if region == NO_REGION or region == nil then return "no region" end
        return tostring(region)
    end

    -- Rooms the scope covers, warm or claimed: "3 of 16 rooms (region greenhollow, regions around it: 0)"
    local function coverage()
        if not region_of then return string.format("%d of %d rooms", total, total) end
        local count = 0
        for id in pairs(rooms) do
            if wanted(id) then count = count + 1 end
        end
        return string.format("%d of %d rooms (region %s, regions around it: %d)",
            count, total, region_name(center_region), adjacent)
    end

    local reported = false
    local function report_first_pass()
        if reported then return end
        reported = true
        M.log(string.format("[ROOM_MANAGER] Startup warming finished: scope %s, %s",
            region_of and "region" or "all", coverage()))
    end

    local function enqueue_wanted()
        for _, id in ipairs(sorted_ids(rooms)) do
            if wanted(id) and not retained[id] and not claimed[id] and not pending[id] then
                pending[id] = true
                queue[#queue + 1] = id
            end
        end
    end

    if region_of then
        local center = opts.center
        center_region = center ~= nil and region_of[center] or nil
        if center_region ~= nil then
            dist = region_distances(adjacency, center_region)
        else
            dist = {}
        end
        enqueue_wanted()
    else
        queue = sorted_ids(rooms)
    end

    -- Sticky: once the first pass has finished, a later retarget never closes
    -- the startup gate again (RoomManager.is_startup_ready gates input).
    function service.ready()
        if first_pass_done then return true end
        if index > #queue and not active then
            first_pass_done = true
            report_first_pass()
            return true
        end
        return false
    end

    function service.claim(id)
        claimed[id] = true
        if retained[id] then
            resources.release(retained[id])
            retained[id] = nil
        end
    end

    -- Follow the player into another region. Leases more than adjacent + 1
    -- regions away are released into the bounded resource cache; rooms that
    -- were claimed and have since unloaded may be warmed again; newly wanted
    -- rooms join the end of the queue. Same region: nothing happens.
    function service.retarget(center)
        if not region_of or center == nil then return end
        local region = region_of[center]
        if region == nil or region == center_region then return end
        center_region = region
        dist = region_distances(adjacency, region)
        M.log("[ROOM_MANAGER] Warming follows the player: " .. coverage())
        for id, owner in pairs(retained) do
            if far(id) and owner ~= active then
                resources.release(owner)
                retained[id] = nil
            end
        end
        local is_loaded = opts.is_loaded
        for id in pairs(claimed) do
            if not (is_loaded and is_loaded(id)) then claimed[id] = nil end
        end
        enqueue_wanted()
    end

    function service.update()
        if index > #queue and not active then
            service.ready()
            return
        end
        local id = active_id or queue[index]
        if not active then
            if pending then pending[id] = nil end
            if claimed[id] or retained[id] or not wanted(id) then index = index + 1; return end
            local url = factory_url(id)
            if not url then
                print('[ROOM_MANAGER] Cannot warm room with missing factory: ' .. id)
                index = index + 1
                return
            end
            active = {}
            active_id = id
            active.resource = resources.acquire(active, url)
            retained[id] = active
        end
        resources.start(active)
        local err = resources.error(active)
        if active.resource.state == 'ready' or err then
            if err then
                -- An unrelated broken room must not prevent starting the game.
                -- Ordinary arrival reports/retries its error when needed.
                print('[ROOM_MANAGER] Room resource warmup failed: ' .. id .. ': ' .. tostring(err))
                resources.release(active)
                retained[id] = nil
            elseif retained[id] == active and far(id) then
                -- The player moved away while this room loaded.
                resources.release(active)
                retained[id] = nil
            end
            active, active_id = nil, nil
            index = index + 1
        end
    end

    function service.release_all()
        reported = true  -- torn down, not finished: no report
        for _, owner in pairs(retained) do resources.release(owner) end
        retained = {}
        active, active_id = nil, nil
        index = #queue + 1
    end

    -- Test and debug view.
    function service.snapshot()
        local held = 0
        for _ in pairs(retained) do held = held + 1 end
        return { queued = #queue, index = index, retained = held, region = center_region }
    end

    return service
end

return M
