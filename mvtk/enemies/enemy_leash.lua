-- Optional return to the original world-space post. Tuning is resolved at
-- spawn/apply, never copied from RuntimeSettings during a frame.
local M = {}

function M.configure(self)
    if self._leash_anchor then return end
    go.update_world_transform()
    local world = go.get_world_position()
    -- Applying a leash later still uses the original post, not today's position.
    local start = self.start_pos or self.pos
    self._leash_anchor = vmath.vector3(world.x + start.x - self.pos.x,
        world.y + start.y - self.pos.y, world.z)
end

function M.update(self, dt)
    local cfg = self._roster
    if not cfg or (cfg.leash_distance or 0) <= 0 or not self._leash_anchor
        or self._ambush_hidden or dt <= 0 then return end
    if (self._leash_cooldown or 0) > 0 then
        self._leash_cooldown = math.max(0, self._leash_cooldown - dt)
        self._player_detected, self._simple_movement_state = false, "idle"
        self.vel.x = 0
        if not self._grounded_movement then self.vel.y = 0 end
        return
    end
    local dx, dy = self._leash_anchor.x-self.pos.x, self._leash_anchor.y-self.pos.y
    local distance = math.sqrt(dx*dx+dy*dy)
    local chasing = self._simple_movement_state == "chase" or self._player_detected == true
    if not self._leash_returning then
        if chasing and distance > cfg.leash_distance then
            self._leash_elapsed = (self._leash_elapsed or 0) + dt
        else self._leash_elapsed = 0 end
        if not chasing or distance <= cfg.leash_distance or self._leash_elapsed < cfg.leash_time then return end
        self._leash_returning = true
    end
    self._player_detected, self._simple_movement_state = false, "return"
    -- Grounded actors walk home horizontally; gravity owns their vertical arc,
    -- so they arrive by that same distance even when the post is off their floor.
    local remaining = self._grounded_movement and math.abs(dx) or distance
    if remaining <= cfg.leash_arrival_px then
        self._leash_returning, self._leash_elapsed = false, 0
        self._leash_cooldown = cfg.leash_cooldown
        self.vel.x = 0
        if not self._grounded_movement then self.vel.y = 0 end
        return
    end
    local speed = (self.speed or 80) * (self._speed_mult or 1) * (self._elite_speed_mult or 1)
    speed = math.min(speed, remaining/dt)
    self.facing = dx < 0 and -1 or 1
    if self._grounded_movement then self.vel.x = self.facing*speed
    else self.vel.x,self.vel.y = dx/distance*speed,dy/distance*speed end
end

return M
