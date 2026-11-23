-- Pure axis policy shared by ladder payloads and player movement.
local Timers = require "mvtk.player.timers"
local M = {}

function M.axis_for(kind)
    if kind == "hang_bar" then return "hang" end
    if kind == "climb_mesh" then return "mesh" end
    return "vertical"
end

function M.payload(props)
    if M.axis_for(props.ladder_type) == "hang" then
        return { snap_to_center = false, pass_through_top = false,
            can_jump_off = false, jump_lets_go = props.can_jump_off ~= false }
    elseif M.axis_for(props.ladder_type) == "mesh" then
        return { snap_to_center = false }
    end
    return {}
end

-- How far below a hang bar's centre line the player's origin hangs: Game
-- Settings > Advanced > Hang bar > Hang offset, else the ladder's hand height
-- (Stage 9 A49). cfg is the scaled ladder_climb table, so both follow Player Size.
function M.hang_offset(self, cfg)
    cfg = cfg or {}
    local px = tonumber(cfg.hang_offset_px) or 0
    if px > 0 then return px end
    return (tonumber(cfg.hand_height_ratio) or 1) * (self.collider_half_height or 60)
end

function M.enter_extend(self, cfg)
    local offset = M.hang_offset(self, cfg)
    self._climb_grab_extend_down = math.max(self._climb_grab_extend_down or 0, offset + 16)
    return offset
end

local function horizontal(self, move, speed, dt)
    local center = self._climb_center_x or self.pos.x
    local half = (self._climb_width or 0) * 0.5
    local lo, hi = center - half, center + half
    self.pos.x = math.max(lo, math.min(hi, self.pos.x))
    local target = math.max(lo, math.min(hi, self.pos.x + move * speed * dt))
    self.vx = dt > 0 and (target - self.pos.x) / dt or 0
    if move ~= 0 then self.facing = move < 0 and -1 or 1 end
end

function M.update(self, input, dt, cfg)
    if not self._in_climb then return false end
    local axis = self._climb_axis
    if axis ~= "hang" and axis ~= "mesh" then return false end
    self._jump_cut_pending = nil
    if axis == "hang" then
        local offset = M.enter_extend(self, cfg)
        self._climb_top_pass_active = false
        self.bypass_ceiling_frames = 0
        if (input.jump_down and self._climb_jump_lets_go)
            or ((input.move_y or 0) < -0.5 and self._climb_drop_on_down) then
            self._in_climb = false
            Timers.extend_window(self, "_climb_reattach_lock_t", 0.25)
            self.vy = 0
            input.jump_down = false
            return true
        end
        local target = (self._climb_center_y or self.pos.y + offset) - offset
        self.pos.y = self.pos.y + (target - self.pos.y) * Timers.center_fraction(18, dt)
        self.vy = 0
        horizontal(self, input.move_x or 0, self._climb_hang_speed or 260, dt)
    else
        horizontal(self, input.move_x or 0, self._climb_speed or 200, dt)
        self.vy = (input.move_y or 0) * (self._climb_speed or 200)
    end
    return true
end

return M
