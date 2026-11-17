-- Engine-free wave scheduler. The adapter owns world effects and persistence.
-- Each successful spawn must end in defeat; disappearing actors cancel a fight.
local M = {}

function M.new(callbacks, persisted)
    return {state=persisted and "cleared" or "idle", callbacks=callbacks, clear_count=0,
        ids={}, queue={}, waves={}}
end

local function wave(self)
    self.wave_index = self.wave_index + 1
    local number = self.waves[self.wave_index]
    if not number then
        self.state = "cleared"
        self.clear_count = self.clear_count + 1
        self.callbacks.clear(self.clear_count)
        return
    end
    self.queue, self.wave_time = {}, 0
    for _, point in ipairs(self.points) do
        if point.encounter_wave == number then
            for i=1, math.max(0, math.floor(point.spawn_count)) do
                self.queue[#self.queue+1] = {point=point,
                    due=math.max(0, point.spawn_delay) + (i-1)*math.max(0, point.spawn_interval)}
            end
        end
    end
    table.sort(self.queue, function(a,b)
        if a.due ~= b.due then return a.due < b.due end
        return a.point.spawn_id < b.point.spawn_id
    end)
    self.state = "spawning"
    self.callbacks.wave(self.wave_index, #self.waves)
end

function M.start(self, points, settings, repeatable)
    if self.state ~= "idle" and not (repeatable and self.state == "cleared") then return false end
    self.points, self.settings = points, settings
    self.ids, self.queue, self.waves = {}, {}, {}
    local seen = {}
    for _, point in ipairs(points) do
        if not seen[point.encounter_wave] then
            seen[point.encounter_wave] = true
            self.waves[#self.waves+1] = point.encounter_wave
        end
    end
    table.sort(self.waves)
    self.wave_index, self.timer = 0, settings.start_delay
    self.state = "starting"
    self.callbacks.start()
    return true
end

function M.reset(self, reason, persisted)
    self.state = persisted and "cleared" or "idle"
    self.ids, self.queue = {}, {}
    self.callbacks.reset(reason)
end

function M.update(self, dt)
    if self.state == "idle" or self.state == "cleared" then return end
    -- Include owner-inheriting helpers, without losing ids the service forgot.
    local seen = {}
    for _, id in ipairs(self.ids) do seen[id] = true end
    for _, id in ipairs(self.callbacks.list()) do
        if not seen[id] then self.ids[#self.ids+1] = id; seen[id] = true end
    end
    -- Check every created actor, including earlier waves, before advancing.
    for _, id in ipairs(self.ids) do
        local outcome = self.callbacks.outcome(id)
        if outcome == nil or outcome == "gone" then M.reset(self, "spawn_gone"); return end
    end
    if self.state == "starting" or self.state == "wave_delay" then
        self.timer = self.timer - dt
        if self.timer > 0 then return end
        wave(self)
        return
    end
    self.wave_time = self.wave_time + dt
    local alive, reserved = self.callbacks.count_alive(), 0
    for _, entry in ipairs(self.queue) do
        if entry.telegraph and not entry.resolved then reserved = reserved + 1 end
    end
    for _, entry in ipairs(self.queue) do
        if not entry.resolved then
            if not entry.telegraph and self.wave_time >= entry.due
                and alive + reserved < self.settings.max_alive then
                entry.telegraph = self.wave_time
                reserved = reserved + 1
                self.callbacks.telegraph(entry.point)
            end
            if entry.telegraph and self.wave_time - entry.telegraph >= self.settings.spawn_telegraph_time then
                local id = self.callbacks.spawn(entry.point, self.waves[self.wave_index])
                entry.resolved = true
                reserved = reserved - 1
                if id then self.ids[#self.ids+1] = id; alive = alive + 1 end
                -- A rejected spawn is resolved: the service warns once, never retry forever.
            end
        end
    end
    for _, entry in ipairs(self.queue) do if not entry.resolved then return end end
    self.state = "wave_active"
    -- Owner totals also include helpers spawned by wave enemies.
    if self.callbacks.count_alive() > 0 then return end
    if self.callbacks.count_defeated() < #self.ids then return end
    for _, id in ipairs(self.ids) do
        if self.callbacks.outcome(id) ~= "defeated" then return end
    end
    if self.wave_index == #self.waves then wave(self)
    else self.state, self.timer = "wave_delay", self.settings.wave_delay end
end

return M
