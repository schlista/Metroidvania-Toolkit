-- Live world-space water rectangles. Keys are baked gameobject ids, so streamed
-- volumes sharing a switch channel remain independent. No engine dependency.
local M = {}
local volumes = {}
local levels = {}
local current_sources = {}
local player_life, player_alive = 0, true

function M.set_player_alive(alive)
    if player_alive == alive then return end
    player_life, player_alive = player_life + 1, alive
end

-- A motion reset can keep the same native overlap. Give it a new contact
-- lifetime so the volume can report itself again without a trigger edge.
function M.begin_player_life()
    player_life, player_alive = player_life + 1, true
end

function M.player_life() return player_life, player_alive end

function M.register(id, volume, current_source)
    volumes[id], levels[id], current_sources[id] = volume, nil, current_source
end
function M.update(id, volume) volumes[id] = volume end
function M.unregister(id) volumes[id], levels[id], current_sources[id] = nil, nil, nil end
function M.has(id) return volumes[id] ~= nil end

function M.damage_ticks(start, now, interval)
    local due = math.floor((now - start) / interval)
    -- Compare absolute deadlines on both sides of a rounding boundary.
    if start + due * interval > now then return due end
    if start + (due + 1) * interval <= now then return due + 2 end
    return due + 1
end

function M.retire_player_damage()
    for _, source in pairs(current_sources) do
        if source._damage_clocks then
            for url, clock in pairs(source._damage_clocks) do
                if clock.life then source._damage_clocks[url] = nil end
            end
        end
    end
end

-- The player is the authority for respawn grace at message delivery.
function M.reject_timed_damage(message)
    local source = current_sources[message.water_source]
    if source and source._damage_clocks then source._damage_clocks[message.water_target] = nil end
end

function M.resume_timed_damage(message, protected_fraction)
    local source = current_sources[message.water_source]
    local clocks = source and source._damage_clocks
    local clock = clocks and clocks[message.water_target]
    if not clock then return 0 end
    local now = source._damage_time
    local start = now - message.water_dt * (1 - protected_fraction)
    clock.start = start
    clock.paid = M.damage_ticks(start, now, source.damage_interval_value)
    return source.damage * clock.paid
end

local function find(x, y, margin, sample)
    margin = margin or 0
    local highest, surface, highest_id
    for id, volume in pairs(volumes) do
        if x >= volume.left - margin and x <= volume.right + margin
            and y >= volume.bottom - margin then
            local height = sample and sample(id, volume) or volume.surface_y
            if not highest or height > surface then highest, surface, highest_id = volume, height, id end
        end
    end
    local source = highest_id and current_sources[highest_id]
    if source then
        highest.current_direction, highest.current_strength = source.current_direction, source.current_strength
    end
    return highest, surface
end

function M.find(x, y, margin)
    local volume = find(x, y, margin)
    return volume
end

function M.record_level(id, frame, dt, step, before, predict)
    local volume = volumes[id]
    if not volume or not frame then return end
    local level = levels[id]
    if not level then
        level = {time=0, samples={{time=0, y=before or volume.surface_y}}}
        levels[id] = level
    end
    level.frame, level.time = frame, level.time + dt
    level.predict = predict
    local samples = level.samples
    local tail = samples[#samples]
    if tail and tail.time == level.time then tail.y = volume.surface_y
    else samples[#samples+1] = {time=level.time, y=volume.surface_y} end
    while #samples > 2 and samples[2].time < level.time - 2*step do table.remove(samples, 1) end
end

-- A floating object stepped ahead of its water source saw the previous
-- water update at 60 Hz. Sample the same point in that source's history.
function M.find_for_float(x, y, frame, dt, step)
    if not frame or math.abs(dt-step) <= 1e-12 then return M.find(x, y) end
    return find(x, y, 0, function(id, volume)
        local level = levels[id]
        if not level or level.frame == frame then return volume.surface_y end
        local difference = dt-step
        if difference > 0 and level.predict then return level.predict(difference) end
        local at = level.time + difference
        local samples = level.samples
        for i=#samples-1,1,-1 do
            local a, b = samples[i], samples[i+1]
            if a.time <= at then
                return a.y + (b.y-a.y) * (at-a.time) / (b.time-a.time)
            end
        end
        return samples[1].y
    end)
end

return M
