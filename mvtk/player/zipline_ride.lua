-- Velocity-owned ride: normal integration, streaming and terrain resolution run.
local M = {}
local function state(self)
    return self._host and self._host.features.zipline
end
local function cfg(self) return (self._cfg or {}).zip_line or {} end

local function point(s, distance)
    for i, segment in ipairs(s.segments) do
        if distance <= segment.finish or i == #s.segments then
            local t = math.max(0, math.min(segment.length, distance - segment.start))
            return segment.a.x + segment.tx*t, segment.a.y + segment.ty*t, segment
        end
    end
end

function M.active(self) local s=state(self); return s and s.active == true or false end

function M.stop(self, reason)
    local s=state(self)
    if not s or not s.active then return end
    s.active, s.release_frame = false, false
    self._control_locked = false
    if reason == "end" or reason == "jump" then
        local _, _, tangent = point(s, s.progress)
        self.vx, self.vy = tangent.tx*s.exit_boost, tangent.ty*s.exit_boost
        if reason == "jump" then self.vy = cfg(self).release_jump_speed or 900 end
        s.release_frame = reason == "jump"
    end
    s.reason = reason
end

function M.start(self, message)
    local s=state(self)
    local compact = self._host and self._host.features.compact_form
    if not s or s.active or require("mvtk.core.pause").get() or self._is_dead
        or self._in_water or self._in_climb or self._ledge_kinematic or self._ledge_hanging
        or self._block_grab or (self._stun_t or 0)>0 or self._room_arrival
        or (self._dash_t or 0)>0 or (self._slide_t or 0)>0 or (self._roll_t or 0)>0
        or (self._backdash_t or 0)>0
        or self._super_jump_rising or self._pound_active or (compact and (compact.roll or 0)>0)
        then return false end
    local segments, length, previous = {}, 0, nil
    local points=message.points or require("mvtk.player.zipline_paths").get(message.points_key) or {}
    for _, p in ipairs(points) do
        if previous then
            local dx,dy=p.x-previous.x,p.y-previous.y
            local n=math.sqrt(dx*dx+dy*dy)
            if n>0 then
                segments[#segments+1]={a={x=previous.x,y=previous.y},length=n,start=length,
                    finish=length+n,tx=dx/n,ty=dy/n}
                length=length+n
            end
        end
        previous=p
    end
    if #segments==0 or (tonumber(message.speed) or 0)<=0 then return false end
    require("mvtk.player.player_grapple").clear(self)
    self._grapple_recast_t, self._anim_lock_t = 0, 0
    self.vx, self.vy = 0, 0
    s.segments,s.length,s.progress,s.stalled=segments,length,0,0
    s.speed,s.exit_boost=message.speed,tonumber(message.exit_boost) or 0
    s.hang,s.animation=cfg(self).hang_offset_px or 70,cfg(self).animation or "grapple"
    s.health=self.health
    s.active,s.release_frame=true,false
    self._control_locked=true
    self.pos.x,self.pos.y=segments[1].a.x,segments[1].a.y-s.hang
    if segments[1].tx~=0 then self.facing=segments[1].tx>0 and 1 or -1 end
    return true
end

local function clear_input(self, input)
    for _, key in ipairs({"light_down","light_held","light_up","heavy_down","heavy_held","heavy_up",
        "ranged_down","ranged_held","ranged_up","parry_down","grapple_down","grapple_held",
        "slide_down","slide_held","slide_up","dash_down","dash_pressed","backdash_down",
        "ground_pound_down","interact_down","potion_down","marker_down","morph_toggle_down"}) do
        input[key]=false
    end
    input.move_x,input.move_y=0,0
    self._light_buffer_count,self._heavy_buffer_count,self._ranged_buffer_count=0,0,0
    self._conveyor_contacts=nil
    self._ext_fx,self._ext_fy=0,0
    if self._env_contacts then self._env_contacts.push=nil end
    self._climb_reattach_lock_t=math.max(self._climb_reattach_lock_t or 0,0.2)
end

function M.pre_physics(self, dt, input)
    if require("mvtk.core.pause").get() then return end
    if not M.active(self) then return end
    local s=state(self)
    local damaged=s.health and self.health and self.health<s.health
    s.health=self.health
    if damaged or self._is_dead or self._in_water or self._in_climb or (self._stun_t or 0)>0 then
        M.stop(self,"cancel"); return
    end
    local jump=input.jump_down and cfg(self).release_on_jump~=false
    clear_input(self,input)
    -- Jump cannot spend an air jump in PSTATE in the release frame.
    input.jump_down=false
    if jump then M.stop(self,"jump") end
end

function M.owns_motion(self, dt)
    local s=state(self)
    if not s or require("mvtk.core.pause").get() then return false end
    if s.release_frame then return true end
    if not s.active or dt<=0 then return s.active == true end
    s.step_x,s.step_y=self.pos.x,self.pos.y
    s.pending=math.min(s.length,s.progress+s.speed*dt)
    local x,y,tangent=point(s,s.pending)
    -- A whole hairpin can return to its start within one frame. Request a real
    -- intermediate move instead, so successful travel and seam refusal remain
    -- distinguishable from the actual position in post_physics.
    if (x-self.pos.x)^2+(y-s.hang-self.pos.y)^2<=0.00000001 then
        for _,segment in ipairs(s.segments) do
            if segment.finish>s.progress and segment.finish<s.pending then
                local px,py=point(s,segment.finish)
                if (px-self.pos.x)^2+(py-s.hang-self.pos.y)^2>0.00000001 then
                    s.pending=segment.finish
                    x,y,tangent=point(s,s.pending)
                    break
                end
            end
        end
    end
    self.vx,self.vy=(x-self.pos.x)/dt,(y-s.hang-self.pos.y)/dt
    if tangent.tx~=0 then self.facing=tangent.tx>0 and 1 or -1 end
    return true
end

function M.post_physics(self, dt)
    local s=state(self)
    if not s or require("mvtk.core.pause").get() then return end
    s.release_frame=false
    if not s.active or not s.pending or dt<=0 then return end
    -- Only search the requested interval. Never advance from an attempted move
    -- that the seam guard or collision solver refused.
    local best, best_distance=s.progress,math.huge
    local px,py=self.pos.x,self.pos.y+s.hang
    local moved=(self.pos.x-(s.step_x or self.pos.x))^2+(self.pos.y-(s.step_y or self.pos.y))^2
    local target_x,target_y=point(s,s.pending)
    if moved>0.00000001 and (px-target_x)^2+(py-target_y)^2<=0.00000001 then
        -- At a repeated path point, a completed nonzero move commits the
        -- requested interval. A zero-displacement refused move never does.
        best=s.pending
    elseif moved>0.00000001 then
        for _, segment in ipairs(s.segments) do
            if segment.finish>=s.progress and segment.start<=s.pending then
                local along=(px-segment.a.x)*segment.tx+(py-segment.a.y)*segment.ty
                local distance=math.max(s.progress,math.min(s.pending,segment.start+math.max(0,math.min(segment.length,along))))
                local x,y=point(s,distance)
                local error_sq=(px-x)^2+(py-y)^2
                if error_sq<best_distance then best,best_distance=distance,error_sq end
            end
        end
    end
    if best-s.progress>0.0001 then s.stalled=0 else s.stalled=s.stalled+1 end
    s.progress=best
    if s.progress>=s.length-0.0001 then M.stop(self,"end")
    elseif s.stalled>=4 then M.stop(self,"blocked") end
end

function M.reset(self, reason)
    M.stop(self,reason)
    local s=state(self)
    if s then s.active,s.release_frame,s.pending=false,false,nil end
end
return M
