-- World pacing lint: long stretches without a save, rooms no route reaches,
-- and empty dead ends. Pure and LuaJ-safe (no frontier patterns, no precision formats).
-- It reads the progression graph's edges, so doors, elevators, zip lines,
-- vehicles and teleporters all connect rooms. Fast travel does not: a station
-- must be reached on foot before it works. Gates and requirements are ignored.
-- Diagnostics are warnings and info only; they never block publication.
local M = {}

-- Objects that let the player save or respawn, so a stretch starts again.
M.ANCHORS = { save_point = true, checkpoint = true, fast_travel = true }
-- World census kinds that make a one-exit room worth the trip.
M.CONTENT = { item = true, chest = true, lore = true, secret = true, boss = true, trial = true,
    map_station = true, shop = true, upgrade_station = true, skill_trainer = true,
    offering_altar = true, bank = true, health_station = true, energy_station = true, npc = true }
-- Rooms named on one aggregated line, so a long world cannot crowd out
-- other lines in Preparation Status.
M.MAX_LISTED = 6

local function listing(rooms)
    local shown = {}
    for i = 1, math.min(#rooms, M.MAX_LISTED) do shown[i] = rooms[i] end
    local text = table.concat(shown, ", ")
    if #rooms > #shown then text = text .. " and " .. string.format("%d", #rooms - #shown) .. " more" end
    return text
end

local function plural(count, one, many)
    return string.format("%d", count) .. " " .. (count == 1 and one or many)
end

-- graph: progression_graph.build result; index: relationship index (objects);
-- layout: the published or candidate layout; pacing: world_lint.lua's pacing block.
function M.check(graph, index, layout, pacing)
    local out = {}
    pacing = pacing or {}
    if pacing.enabled ~= true or not graph or not graph.start or not graph.areas[graph.start] then return out end
    local order = {}
    local placed = {}
    for _, r in ipairs((layout or {}).rooms or {}) do
        if r.id ~= nil and not placed[r.id] then order[#order + 1] = r.id; placed[r.id] = true end
    end
    if #order == 0 then return out end
    local forward, near = {}, {}
    for _, id in ipairs(order) do forward[id] = {}; near[id] = {} end
    for _, e in ipairs(graph.edges or {}) do
        local from, to = graph.areas[e.from], graph.areas[e.to]
        local a, b = from and from.room, to and to.room
        if e.kind ~= "fast_travel" and a and b and a ~= b and placed[a] and placed[b] then
            forward[a][b] = true; near[a][b] = true; near[b][a] = true
        end
    end
    local function walk(starts, links)
        local dist, queue, head = {}, {}, 1
        for _, id in ipairs(starts) do
            if dist[id] == nil then dist[id] = 0; queue[#queue + 1] = id end
        end
        while queue[head] do
            local id = queue[head]; head = head + 1
            for _, next_id in ipairs(order) do
                if links[id][next_id] and dist[next_id] == nil then
                    dist[next_id] = dist[id] + 1; queue[#queue + 1] = next_id
                end
            end
        end
        return dist
    end
    local start_room = graph.areas[graph.start].room
    local anchors, anchored, content = {}, {}, {}
    local function anchor(id)
        if placed[id] and not anchored[id] then anchored[id] = true; anchors[#anchors + 1] = id end
    end
    anchor(start_room)
    local kinds = require("developer.tools.world_census").KINDS
    for _, o in ipairs((index or {}).objects or {}) do
        if o.visible and placed[o.room] then
            if o.top_level and M.ANCHORS[o.type] then anchor(o.room) end
            if M.CONTENT[kinds[o.type] or ""] then content[o.room] = true end
        end
    end

    local reached = walk({ start_room }, forward)
    local unreachable = {}
    for _, id in ipairs(order) do if reached[id] == nil then unreachable[#unreachable + 1] = id end end
    if #unreachable > 0 then
        out[#out + 1] = { severity = "warning", code = "pacing_unreachable_room",
            message = plural(#unreachable, "placed room has", "placed rooms have") ..
                " no door, elevator, vehicle or teleporter route from the start room (" ..
                start_room .. "; fast travel and gates ignored): " .. listing(unreachable) .. "." }
    end

    local limit = tonumber(pacing.max_rooms_without_save) or 8
    local hops = walk(anchors, near)
    local far = {}
    for _, id in ipairs(order) do if hops[id] and hops[id] > limit then far[#far + 1] = id end end
    if #far > 0 then
        out[#out + 1] = { severity = "warning", code = "pacing_rooms_without_save",
            message = plural(#far, "room is", "rooms are") .. " more than " .. string.format("%d", limit) ..
                " room hops from a save point, checkpoint, fast travel station or the start room: " ..
                listing(far) .. ". Hops ignore room size; see pacing in developer/config/world_lint.lua." }
    end

    if pacing.dead_end_info ~= false then
        for _, id in ipairs(order) do
            local exits = 0
            for _, other in ipairs(order) do if near[id][other] then exits = exits + 1 end end
            if exits == 1 and not anchored[id] and not content[id] then
                out[#out + 1] = { severity = "info", code = "pacing_dead_end_room", room = id,
                    message = "Dead end with one exit and no save point, reward, map station, vendor or other counted content." }
            end
        end
    end
    return out
end

return M
