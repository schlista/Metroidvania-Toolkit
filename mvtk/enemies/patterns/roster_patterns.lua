-- Surface and hidden movement share the ordinary pattern host. All placement
-- tuning lives on the actor, so name-only pattern reconstruction is sufficient.
-- Not a literal require: attack_patterns requires this module, and Bob refuses require cycles.
local ATTACK_PATTERNS_MODULE = "mvtk.enemies.patterns.attack_patterns"
local M = {}
local H = {}
M._helpers = H

local function inherited(value)
    return value == nil or value == "" or value == "type_default" or value == "none"
end

local function clip(self, choices, once)
    if self.play_roster_animation then self.play_roster_animation(self, choices, once) end
end

local function hide(self)
    local Util = require "mvtk.core.util"
    self._ambush_hidden = true -- posts below are asynchronous, including collision disable
    Util.post_component_enabled("#co", false)
    Util.post_component_enabled("#sprite", self._roster.ambush_style == "disguise")
    if self._roster.ambush_style == "disguise" then clip(self, {"disguise", "idle"}) end
end

function H.reset(self)
    local restore_components = self._ambush_hidden
    if self._surface_crawling then
        self._ignores_terrain = (self.enemy_type_config or {}).ignores_terrain == true
    end
    self._crawl, self._ambush_follow = nil, nil
    self._ambush_dropping = nil
    self._hop, self._swim_volume, self._swim_warned = nil, nil, nil
    self._swarm_inner, self._swarm_inner_name = nil, nil
    self._swim_movement = false
    self._leash_returning, self._leash_elapsed, self._leash_cooldown = false, 0, 0
    self._surface_crawling, self._ambush_hidden = false, false
    self._ambush_released, self._ambush_signal = false, false
    for _, pattern in ipairs(self.patterns or {}) do
        if pattern.name == "surface_crawl" then
            self._surface_crawling, self._ignores_terrain = true, true
        elseif pattern.name == "swim" then
            self._swim_movement = true
        elseif pattern.name == "ambush" then
            hide(self)
            restore_components = false
        end
    end
    if restore_components then
        local Util = require "mvtk.core.util"
        Util.post_component_enabled("#sprite", true)
        Util.post_component_enabled("#co", true)
    end
    if self._ambush_trigger_id and self._ambush_trigger_id ~= "" then
        require("mvtk.world.switch_state").replay(require("mvtk.core.flags"),
            self._ambush_trigger_id, function(on) if on == true then self._ambush_signal = true end end)
    end
end

function H.configure(self, overrides)
    local defaults = require("developer.config.runtime_settings").section(
        "enemy_defaults", require "developer.config.enemy_defaults")
    local cfg = self.enemy_type_config or {}
    local tuning = {}
    for _, key in ipairs({"crawl_speed", "cling_side", "ambush_style", "ambush_range", "ambush_trigger_id",
        "swim_speed", "hop_height", "hop_interval", "leash_distance", "leash_time"}) do
        local value = overrides[key]
        if value ~= nil then self[key] = value end
        value = self[key]
        if inherited(value) or (type(value) == "number" and value < 0) then value = cfg[key] end
        if inherited(value) then value = defaults[key] end
        tuning[key] = value
    end
    tuning.crawl_skin_px = defaults.crawl_skin_px
    tuning.crawl_half_height_px = defaults.crawl_half_height_px
    tuning.crawl_probe_tiles = defaults.crawl_probe_tiles
    tuning.swim_margin_px = defaults.swim_margin_px
    tuning.hop_prepare_time, tuning.hop_land_time = defaults.hop_prepare_time, defaults.hop_land_time
    tuning.leash_cooldown = defaults.leash_cooldown
    -- Config-only swarm tuning persists across name-only revival. Resolve it
    -- here, never by copying RuntimeSettings during an update.
    for _, key in ipairs({"swarm_ring_radius", "swarm_separation", "swarm_cohesion"}) do
        tuning[key] = cfg[key] or defaults[key]
    end
    tuning.swarm_leader_movement = cfg.swarm_leader_movement or "chase_flying"
    local tile = require "developer.config.tile_settings"
    tuning.leash_arrival_px = (tile.width or tile.size or 64) * 0.5
    tuning.ambush_then = cfg.ambush_then or (self._grounded_movement and "chase_ground" or "chase_flying")
    self._roster = tuning
    if (tuning.leash_distance or 0) > 0 then require("mvtk.enemies.enemy_leash").configure(self) end
    local channel = tuning.ambush_trigger_id or ""
    if self._ambush_url and channel ~= self._ambush_trigger_id then
        require("mvtk.world.trigger_bus").unregister(self._ambush_trigger_id, self._ambush_url)
        self._ambush_url = nil
    end
    self._ambush_trigger_id = channel
    if channel ~= "" and not self._ambush_url then
        self._ambush_url = msg.url()
        require("mvtk.world.trigger_bus").register(channel, self._ambush_url)
    end
    H.reset(self)
end

local function swarm_leader(self, dt)
    local name = self._roster.swarm_leader_movement
    if self._swarm_inner_name ~= name then
        local meta = require("mvtk.enemies.enemy_behavior_resolver").PATTERN_META[name]
        local factory = require(ATTACK_PATTERNS_MODULE)[hash(name)]
        -- Only movement patterns may run inside swarm. Prevent recursive swarm
        -- or ambush nesting, and keep attacks under the ordinary host's leash.
        self._swarm_inner = factory and meta and meta.role == "movement"
            and name ~= "swarm" and name ~= "ambush" and factory() or {}
        self._swarm_inner_name = name
    end
    if self._swarm_inner.update then self._swarm_inner.update(self, dt) end
end

function M.swarm()
    return {update=function(self, dt)
        if dt <= 0 then return end
        local Groups = require "mvtk.enemies.group_coordination"
        local group = Groups.get_group(self.spawn_id)
        if not group or Groups.is_leader(self.spawn_id) then
            -- Ungrouped placements still move; Prepare & Check warns the creator.
            swarm_leader(self, dt)
            return
        end
        self._swarm_inner, self._swarm_inner_name = nil, nil
        local Manager = require "mvtk.enemies.enemy_manager"
        local leader = Manager.get_enemy(group.leader)
        if not leader or not leader.position then self.vel.x,self.vel.y=0,0;return end
        local members = Groups.get_members(group.id)
        table.sort(members)
        local index, count = 0, 0
        local sx, sy, neighbors = 0, 0, 0
        local cfg, pos = self._roster, self.pos
        for _, id in ipairs(members) do
            if id ~= group.leader then
                count = count + 1
                if id == self.spawn_id then index = count end
            end
            if id ~= self.spawn_id then
                local other = Manager.get_enemy(id)
                local p = other and other.position
                if p then
                    local dx,dy=pos.x-p.x,pos.y-p.y
                    local distance=math.sqrt(dx*dx+dy*dy)
                    if distance > 0 and distance < cfg.swarm_separation then
                        sx,sy,neighbors=sx+dx/distance,sy+dy/distance,neighbors+1
                    end
                end
            end
        end
        if index == 0 then return end
        local angle = (index-1)*2*math.pi/math.max(1,count)
        local dx = leader.position.x + math.cos(angle)*cfg.swarm_ring_radius-pos.x
        local dy = leader.position.y + math.sin(angle)*cfg.swarm_ring_radius-pos.y
        local distance = math.sqrt(dx*dx+dy*dy)
        local speed = (self.speed or 80)*(self._speed_mult or 1)*(self._elite_speed_mult or 1)
        local vx,vy=0,0
        if distance > 0 then
            local steer=math.min(speed,distance/dt)
            vx,vy=dx/distance*steer,dy/distance*steer
        end
        if neighbors > 0 then
            vx,vy=vx+sx/neighbors*cfg.swarm_cohesion*speed,vy+sy/neighbors*cfg.swarm_cohesion*speed
        end
        local magnitude=math.sqrt(vx*vx+vy*vy)
        if magnitude > speed then vx,vy=vx/magnitude*speed,vy/magnitude*speed end
        self.vel.x,self.vel.y=vx,vy
        self._player_detected,self._simple_movement_state=false,"swarm"
        if vx ~= 0 then self.facing = vx < 0 and -1 or 1 end
    end}
end

local function water_at(x, y)
    local volume = require("mvtk.world.water_registry").find(x,y)
    if volume and y <= volume.surface_y then return volume end
end

-- Run after all velocity owners (including attacks and leash) so even their
-- impulses cannot take a swimmer outside its live water rectangle.
function H.constrain_swim(self, dt)
    if dt <= 0 then return end
    local volume = water_at(self.pos.x,self.pos.y)
    self._swim_volume = volume
    if not volume then
        self.vel.x,self.vel.y = 0,0
        self._player_detected,self._simple_movement_state = false,"idle"
        if not self._swim_warned then
            print("[ENEMY] Swim movement has no water at its position; idling.")
            self._swim_warned = true
        end
        return
    end
    self._swim_warned = nil
    local margin = math.max(0,self._roster.swim_margin_px)
    local mx = math.min(margin,(volume.right-volume.left)*0.5)
    local my = math.min(margin,(volume.surface_y-volume.bottom)*0.5)
    local x = math.max(volume.left+mx,math.min(volume.right-mx,self.pos.x+self.vel.x*dt))
    local y = math.max(volume.bottom+my,math.min(volume.surface_y-my,self.pos.y+self.vel.y*dt))
    self.vel.x,self.vel.y = (x-self.pos.x)/dt,(y-self.pos.y)/dt
end

function M.swim()
    return {update=function(self,dt)
        local volume = water_at(self.pos.x,self.pos.y)
        self.vel.x,self.vel.y = 0,0
        self._player_detected,self._simple_movement_state = false,"patrol"
        if not volume then H.constrain_swim(self,dt);clip(self,{"idle"});return end
        local Detection = require "mvtk.enemies.detection"
        local target = Detection.get_player_position()
        local speed = self._roster.swim_speed * (self._speed_mult or 1) * (self._elite_speed_mult or 1)
        if target and water_at(target.x,target.y) == volume
            and not self._leash_returning and (self._leash_cooldown or 0) <= 0
            and Detection.can_detect_player(self.pos,self._detection_range or 240,false) then
            local dx,dy=target.x-self.pos.x,target.y-self.pos.y
            local distance=math.sqrt(dx*dx+dy*dy)
            self._player_detected,self._simple_movement_state = true,"chase"
            if distance>0 then
                speed=math.min(speed,distance/math.max(dt,0.000001))
                self.vel.x,self.vel.y=dx/distance*speed,dy/distance*speed
            end
        else
            if self.pos.x >= volume.right-self._roster.swim_margin_px then self.facing=-1
            elseif self.pos.x <= volume.left+self._roster.swim_margin_px then self.facing=1 end
            self.vel.x=(self.facing or 1)*speed
        end
        H.constrain_swim(self,dt)
        if self.vel.x ~= 0 then self.facing = self.vel.x < 0 and -1 or 1 end
        clip(self,{"swim","walk","idle"})
    end}
end

function M.hop()
    return {update=function(self,dt)
        local cfg = self._roster
        local state = self._hop
        if not state then state={phase="idle_on_ground",timer=cfg.hop_interval};self._hop=state end
        self.vel.x=0
        if self._leash_returning or (self._leash_cooldown or 0)>0 then return end
        if state.phase == "in_air" then
            if self._airborne then
                self.vel.x=state.direction*(self.speed or 80)*(self._speed_mult or 1)*(self._elite_speed_mult or 1)
            else state.phase,state.timer="land",cfg.hop_land_time;clip(self,{"land","idle"},true) end
            return
        end
        if self._airborne then return end
        state.timer=state.timer-dt
        if state.timer>0 then return end
        if state.phase == "idle_on_ground" then
            state.phase,state.timer="prepare_jump",cfg.hop_prepare_time
            clip(self,{"idle"})
        elseif state.phase == "prepare_jump" then
            local Detection = require "mvtk.enemies.detection"
            local target = Detection.get_player_position()
            local detected = target and Detection.can_detect_player(self.pos,self._detection_range or 240,true)
            self._player_detected,self._simple_movement_state=detected==true,detected and "chase" or "patrol"
            if detected then self.facing=target.x<self.pos.x and -1 or 1
            else
                local distance=self._patrol_distance or (self.enemy_type_config or {}).patrol_distance or 96
                if self.pos.x>self.start_pos.x+distance then self.facing=-1
                elseif self.pos.x<self.start_pos.x-distance then self.facing=1 end
            end
            state.direction=self.facing or 1
            local Ground = require "mvtk.enemies.enemy_ground_physics"
            Ground.launch(self,math.sqrt(2*Ground.gravity()*cfg.hop_height))
            state.phase="in_air"
            self.vel.x=state.direction*(self.speed or 80)*(self._speed_mult or 1)*(self._elite_speed_mult or 1)
            clip(self,{"jump","idle"},true)
        else state.phase,state.timer="idle_on_ground",cfg.hop_interval;clip(self,{"idle"}) end
    end}
end

-- Outward normals. The local top of the actor faces away from its support;
-- its local right is the clockwise tangent. Rotation is parent-relative;
-- the host's existing unparented position contract supplies world ray points.
local SIDES = {floor={0,1}, ceiling={0,-1}, wall_left={1,0}, wall_right={-1,0}}
local function rotate(self, nx, ny)
    local angle = math.atan2(-nx, ny)
    go.set_rotation(vmath.quat_rotation_z(angle))
    self._crawl = {nx=nx, ny=ny}
end

function M.surface_crawl()
    return {update=function(self, dt)
        if dt <= 0 then return end
        local cfg, pos = self._roster, self.pos
        local gap = cfg.crawl_half_height_px * (self._body_scale or 1) + cfg.crawl_skin_px
        local tile = require "developer.config.tile_settings"
        local reach = cfg.crawl_probe_tiles * (tile.height or tile.size or 64)
        local groups = require("mvtk.core.surface_classifier").RAYCAST.TERRAIN
        local function cast(x, y, dx, dy)
            return physics.raycast(vmath.vector3(x,y,pos.z or 0),
                vmath.vector3(x+dx,y+dy,pos.z or 0), groups)
        end
        local state = self._crawl
        if not state then
            local best, normal, distance
            for name, n in pairs(SIDES) do
                if cfg.cling_side == "free" or cfg.cling_side == name then
                    local hit = cast(pos.x,pos.y,-n[1]*reach,-n[2]*reach)
                    if hit then
                        local d = (hit.position.x-pos.x)^2 + (hit.position.y-pos.y)^2
                        if not distance or d < distance then best,normal,distance=hit,n,d end
                    end
                end
            end
            if best then
                pos.x, pos.y = best.position.x+normal[1]*gap, best.position.y+normal[2]*gap
                rotate(self, normal[1], normal[2]); state=self._crawl
            end
        end
        if not state then
            self._surface_crawling, self._ignores_terrain = false, false
            -- Let the single ground-physics pass handle a permitted fall.
            self.vel.x, self.vel.y = 0, 0
            return
        end
        self._surface_crawling, self._ignores_terrain = true, true
        local nx, ny = state.nx, state.ny
        local direction = self.facing < 0 and -1 or 1
        local tx, ty = ny*direction, -nx*direction
        local speed = cfg.crawl_speed * (self._speed_mult or 1) * (self._elite_speed_mult or 1)
        local step = speed*dt
        local forward = cast(pos.x,pos.y,tx*(gap+step),ty*(gap+step))
        local next_x, next_y = pos.x+tx*step, pos.y+ty*step
        if forward then
            -- Concave turn: keep the old support clearance while taking the
            -- new wall's clearance. At most one turn is attempted this frame.
            nx,ny = -tx,-ty
            next_x = pos.x + tx*((forward.position.x-pos.x)*tx+(forward.position.y-pos.y)*ty-gap)
            next_y = pos.y + ty*((forward.position.x-pos.x)*tx+(forward.position.y-pos.y)*ty-gap)
            rotate(self,nx,ny)
        else
            local support = cast(next_x,next_y,-nx*(gap+cfg.crawl_skin_px),-ny*(gap+cfg.crawl_skin_px))
            if support then
                next_x,next_y = support.position.x+nx*gap,support.position.y+ny*gap
            else
                -- Probe back into the outside face from beyond the corner.
                local wrap = cast(next_x-nx*(gap*2),next_y-ny*(gap*2),-tx*(gap+step),-ty*(gap+step))
                if wrap then
                    nx,ny=tx,ty
                    next_x,next_y=wrap.position.x+nx*gap,wrap.position.y+ny*gap
                    rotate(self,nx,ny)
                else
                    self._crawl = nil
                    self._surface_crawling,self._ignores_terrain=false,false
                    self.vel.x,self.vel.y=0,0
                    return
                end
            end
        end
        self.vel.x,self.vel.y=(next_x-pos.x)/dt,(next_y-pos.y)/dt
        clip(self,{"crawl","walk","idle"})
    end}
end

function M.ambush()
    return {update=function(self, dt)
        local cfg = self._roster
        if not self._ambush_released then
            if not self._ambush_hidden then hide(self) end
            self.vel.x,self.vel.y=0,0
            local detected = require("mvtk.enemies.detection").can_detect_player(self.pos,cfg.ambush_range,true)
            if not self._ambush_signal and not detected then return end
            self._ambush_hidden,self._ambush_released=false,true
            local Util = require "mvtk.core.util"
            Util.post_component_enabled("#sprite",true)
            Util.post_component_enabled("#co",true)
            if cfg.ambush_style == "drop" then
                require("mvtk.enemies.enemy_ground_physics").launch(self,0)
                self._ambush_dropping = true
            elseif cfg.ambush_style == "rise" then clip(self,{"emerge","attack","idle"},true)
            else clip(self,{"idle"}) end
        end
        -- Complete the initial vertical drop before chasing. The shared ground
        -- pass clears airborne on landing; chasing in mid-air can miss the floor
        -- the creator placed beneath this enemy.
        if self._ambush_dropping then
            self.vel.x,self.vel.y=0,0
            if self._airborne then return end
            self._ambush_dropping = nil
        end
        if not self._ambush_follow then
            local factory = require(ATTACK_PATTERNS_MODULE)[hash(cfg.ambush_then)]
            -- Invalid or recursive follow-ups stay idle rather than nesting ambush.
            if factory and cfg.ambush_then ~= "ambush" then
                self._ambush_follow = factory()
            else self._ambush_follow = {} end
        end
        if self._ambush_follow.update then self._ambush_follow.update(self,dt) end
    end}
end

return M
