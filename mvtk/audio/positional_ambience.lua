-- Shared positional loops: one voice per ambience id, mixed by loudest source.
-- No engine calls: the controller supplies the listener, settings and driver.
local M = {}
local sources, voices = {}, {}
local settings

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

function M.configure(config) settings = config end

-- Recovered rectangle-edge distance and linear falloff from the former mixer.
function M.distance_to_rect_edge(point, center, width, height)
    local dx = math.max(math.abs((point.x or 0) - (center.x or 0)) - math.max(width or 0, 0) / 2, 0)
    local dy = math.max(math.abs((point.y or 0) - (center.y or 0)) - math.max(height or 0, 0) / 2, 0)
    return math.sqrt(dx * dx + dy * dy)
end

function M.calculate_falloff_gain(dist, start, finish, minimum)
    if dist <= start then return 1 end
    if dist >= finish then return minimum end
    return 1 - (dist - start) / (finish - start) * (1 - minimum)
end

function M.register(key, spec)
    -- Copy the specification; callers and engine vectors may be reused later.
    local s = {}
    for name, value in pairs(spec) do s[name] = value end
    sources[tostring(key)] = s
end

function M.unregister(key) sources[tostring(key)] = nil end

function M.set_position(key, position)
    local s = sources[tostring(key)]
    if s then s.x, s.y = position.x, position.y end
end

function M.listener(camera, player)
    if settings.listener == "camera" and camera.has_value then
        return {x = camera.x, y = camera.y, view_bounds = camera.view_bounds}
    end
    if player then return {x = player.x, y = player.y, view_bounds = camera.view_bounds} end
end

local function pan_distance(listener)
    if settings.pan_distance_px > 0 then return settings.pan_distance_px end
    local b = listener and listener.view_bounds
    local half = b and (b.max_x - b.min_x) / 2
    return half and half > 0 and half or 960
end

function M.update(dt, listener, driver)
    if not settings or not driver then return end
    local targets = {}
    local keys = {}
    for key in pairs(sources) do keys[#keys + 1] = key end
    table.sort(keys) -- Stable pan winner when equally loud sources share an id.
    for _, key in ipairs(keys) do
        local s = sources[key]
        local id = s.ambience_id
        if id and id ~= "" and id ~= "none" then
            local gain, pan = 0, 0
            if listener then
                local dist = M.distance_to_rect_edge(listener, s, (s.half_w or 0) * 2, (s.half_h or 0) * 2)
                gain = clamp(M.calculate_falloff_gain(dist, s.falloff_start, s.falloff_end, s.min_volume) * s.gain, 0, 1)
                pan = clamp((s.x - listener.x) / pan_distance(listener), -1, 1) * settings.pan_strength
            end
            if not targets[id] or gain > targets[id].gain then targets[id] = {gain = gain, pan = pan} end
        end
    end
    for id in pairs(targets) do
        if not voices[id] then voices[id] = {gain = 0, pan = 0} end
    end
    for id, voice in pairs(voices) do
        local target = targets[id]
        if not target then
            -- Last owner unloaded: no orphan loop, even if the controller outlives the room.
            if voice.playing then driver.stop(voice.url) end
            voices[id] = nil
        else
            local step = math.max(0, dt) * settings.fade_per_second
            voice.gain = voice.gain + clamp(target.gain - voice.gain, -step, step)
            voice.pan = target.pan
            local quiet = voice.gain <= settings.stop_below_gain and target.gain <= settings.stop_below_gain
            voice.quiet_frames = quiet and (voice.quiet_frames or 0) + 1 or 0
            if voice.playing then
                if voice.quiet_frames >= 2 then
                    driver.stop(voice.url)
                    voice.playing = false
                else
                    driver.set_gain(voice.url, voice.gain)
                    driver.set_pan(voice.url, voice.pan)
                end
            elseif voice.gain > settings.stop_below_gain then
                voice.url = driver.resolve_url(id)
                if voice.url then
                    -- Setters affect existing voices only; play must carry initial gain/pan.
                    voice.playing = driver.play(voice.url, {gain = voice.gain, pan = voice.pan}) ~= false
                end
            end
        end
    end
end

function M.reset(driver)
    for _, voice in pairs(voices) do
        if voice.playing and driver then driver.stop(voice.url) end
    end
    sources, voices = {}, {}
end

return M
