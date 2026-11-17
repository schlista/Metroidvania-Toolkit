-- Per-instance translating trigger motion. Loaded only by moving hazards.
local Path = require "mvtk.world.kinematic_path"
local M = {}
local Motion = {}
Motion.__index = Motion

local function points(text)
    local out = {}
    for pair in tostring(text or ""):gmatch("[^;]+") do
        local x, y = pair:match("^%s*([^,]+),([^,]+)%s*$")
        x, y = tonumber(x), tonumber(y)
        if not x or not y then return {} end
        out[#out + 1] = {x=x, y=y}
    end
    return out
end

function Motion:place()
    local x, y, state = 0, 0, nil
    if self.kind == "line" or self.kind == "path" then
        local progress
        progress, state = Path.cycle(self.time, self.travel, self.wait, self.mode)
        x, y = Path.at_distance(self.path, self.path.total * progress, false)
    elseif self.kind == "orbit" then
        x, y = Path.orbit(self.pivot_x, self.pivot_y, self.radius, self.angle, self.speed, self.time)
    elseif self.kind == "slam" then
        local offset, shake
        offset, state, shake = Path.slam(self.time, self.timings)
        local fraction = self.distance > 0 and offset / self.distance or 0
        x, y = self.dx * fraction + shake, self.dy * fraction
    end
    self.state = state
    go.set_position(vmath.vector3(self.origin.x + x, self.origin.y + y, self.origin.z))
    -- Contacts and impact FX in this frame must see the moved world transform.
    go.update_world_transform()
end

function Motion:step(owner, dt)
    if require("mvtk.core.pause").get() or owner.base_enabled == false or owner.pattern_active == false then return end
    local before = self.time
    self.time = self.time + math.max(0, dt)
    self:place()
    if self.kind ~= "slam" or dt <= 0 then return end
    local t = self.timings
    local period = t.top + t.warn + t.drop + t.bottom + t.rise
    if period <= 0 then return end
    if self.first_step and before == 0 then before = -0.000000001 end
    self.first_step = false
    -- Include crossed boundaries even if one frame skips an entire warning/drop.
    for cycle = math.max(0, math.floor(before / period)), math.floor(self.time / period) do
        for _, event in ipairs({{at=t.top, sound=self.config.sound_warn},
            {at=t.top + t.warn + t.drop, sound=self.config.sound_crush, impact=true}}) do
            local at = cycle * period + event.at
            if at > before and at <= self.time then
                -- Streaming keeps neighbouring rooms running: like every other timer sound
                -- (prefab_utils.play_sound), a slam is heard, and captioned, only in the player's room.
                if event.sound and event.sound ~= ""
                    and require("mvtk.prefabs.prefab_utils").is_current_room(owner.room_id) then
                    require("mvtk.audio.audio").sfx(event.sound)
                end
                if event.impact and self.config.particle_on_crush then
                    -- The effect belongs at the impact, even when dt advances into rise.
                    local world = go.get_world_position()
                    local local_now = go.get_position()
                    require("mvtk.fx.fx").play(self.config.particle_on_crush,
                        vmath.vector3(world.x + self.origin.x + self.dx - local_now.x,
                            world.y + self.origin.y + self.dy - local_now.y, world.z))
                end
            end
        end
    end
end

function Motion:blocker(position, width, height)
    local x, y, w, h = Path.sweep_bounds(self.spec, width, height)
    return vmath.vector3(position.x + x, position.y + y, position.z), w, h
end

function M.new(owner, origin, config)
    local m = setmetatable({kind=owner.motion_type, origin=vmath.vector3(origin), config=config or {},
        time=math.max(0, owner.motion_offset or 0), wait=math.max(0, owner.motion_wait or 0),
        mode=owner.motion_loop or "pingpong", speed=owner.motion_speed or 200, first_step=true}, Motion)
    m.dx, m.dy = owner.motion_distance_x or 0, -(owner.motion_distance_y or 0)
    m.distance = math.sqrt(m.dx * m.dx + m.dy * m.dy)
    m.spec = {motion_type=m.kind, motion_distance_x=m.dx, motion_distance_y=-m.dy}
    if m.kind == "line" or m.kind == "path" then
        local pts = m.kind == "path" and points(owner.motion_points) or {{x=0,y=0},{x=m.dx,y=m.dy}}
        m.path = Path.polyline(pts, m.kind == "path" and m.mode == "loop")
        m.travel = m.speed ~= 0 and m.path.total / math.abs(m.speed) or 0
        m.spec.points = pts
    elseif m.kind == "orbit" then
        m.pivot_x, m.pivot_y = owner.motion_pivot_x or 0, owner.motion_pivot_y or 0
        if m.pivot_x == 0 and m.pivot_y == 0 then m.pivot_x = -math.abs(owner.motion_radius or 128) end
        m.radius = math.sqrt(m.pivot_x * m.pivot_x + m.pivot_y * m.pivot_y)
        m.angle = math.deg(math.atan2(-m.pivot_y, -m.pivot_x))
        m.spec.motion_pivot_x, m.spec.motion_pivot_y = m.pivot_x, m.pivot_y
    elseif m.kind == "slam" then
        local warn, rest = owner.slam_warn or -1, owner.slam_rest or -1
        m.timings = {top=m.wait, warn=math.max(0, warn >= 0 and warn or m.config.warn_time or 0.5),
            bottom=math.max(0, rest >= 0 and rest or m.config.crush_hold_time or 1), distance=m.distance,
            drop=m.distance / math.max(0.001, owner.slam_drop_speed or 1200),
            rise=m.distance / math.max(0.001, owner.slam_rise_speed or 200)}
    end
    return m
end

return M
