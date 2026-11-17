-- Shared spawn settling and opt-in ground motion. Positions use the same
-- unparented room/world coordinates as enemy.script's movement integration.
local SurfaceClassifier = require "mvtk.core.surface_classifier"
local RuntimeSettings = require "developer.config.runtime_settings"
local TileSettings = require "developer.config.tile_settings"
local Skins = require "developer.config.enemy_skins_generated"
local M = {}
local cached_config, cached_revision

-- section() copies creator overrides: per-frame readers share one snapshot
-- until settings change, just like combat/status_effects.frame_config.
local function frame_config()
    local revision = RuntimeSettings.revision and RuntimeSettings.revision()
    if revision == nil or cached_config == nil or cached_revision ~= revision then
        cached_config = RuntimeSettings.section("enemy_defaults", require "developer.config.enemy_defaults")
        cached_revision = revision
    end
    return cached_config
end

local function inherited(value)
    return value == nil or value == "" or value == "type_default"
end

-- Shared acceleration for explicit launches and the falling integrator.
function M.gravity()
    local tile_h = tonumber(TileSettings.height or TileSettings.tile_height or TileSettings.size) or 64
    return (frame_config().fall_gravity_tiles or 20) * tile_h
end

function M.can_fall(self)
    if not self._grounded_movement or self._ignores_terrain or self._surface_crawling then return false end
    local value = self.ledge_behavior
    if inherited(value) then value = (self.enemy_type_config or {}).ledge_behavior end
    if inherited(value) then value = frame_config().ledge_behavior or "stop" end
    if value == "fall" then return true end
    if value ~= "fall_when_chasing" then return false end
    if self._simple_movement_state ~= nil then return self._simple_movement_state == "chase" end
    return self._player_detected == true
end

-- Explicit impulses (hops and ambush drops) may launch even a stop enemy.
function M.launch(self, vy)
    self._vy = tonumber(vy) or 0
    self._airborne, self._forced_airborne = true, true
end

-- Pattern callback: ordinary jump attacks opt into arcs with falling motion.
-- Keeping the callback on the actor leaves pattern-only hosts independent.
function M.jump(self, vy)
    if not self._airborne and M.can_fall(self) then M.launch(self, vy) end
end

-- nil delegates to the unchanged ledge guard; true means motion was handled.
-- The caller integrates vel exactly once and delivers fall_out through die().
function M.apply(self, dt, raycast)
    if dt <= 0 or self._ignores_terrain or self._surface_crawling then return end
    if not self._forced_airborne and not (self._grounded_movement and
        (self._airborne or M.can_fall(self))) then return end
    local defaults = frame_config()
    local tile_h = tonumber(TileSettings.height or TileSettings.tile_height or TileSettings.size) or 64
    local skin = Skins.skins[self.skin] or Skins.skins.default or {}
    local feet = (skin.feet or 40) * (self._body_scale or 1)
    local clearance = defaults.ground_skin_px or 1
    local step_up = (defaults.step_up_tiles or 0.125) * tile_h
    local step_down = (defaults.step_down_tiles or 0.25) * tile_h
    local pos, vel = self.pos, self.vel
    local floor_y = pos.y - feet - clearance
    local z = pos.z or 0
    raycast = raycast or physics.raycast
    local function cast(x1, y1, x2, y2)
        return raycast(vmath.vector3(x1, y1, z), vmath.vector3(x2, y2, z),
            SurfaceClassifier.RAYCAST.GROUND)
    end
    self._ledge_blocked_dir = nil
    if not self._airborne and (vel.y or 0) > 0 then M.launch(self, vel.y) end
    local next_x = pos.x + vel.x * dt
    local bounds = self._room_bounds
    if bounds and bounds.min_x and bounds.max_x then
        -- Probe where enemy.script's existing horizontal clamp will leave us,
        -- rather than mistaking the space beyond a room side for a pit.
        next_x = math.max(bounds.min_x + 16, math.min(bounds.max_x - 16, next_x))
    end
    if not self._airborne then
        -- Sweep above climbable steps before probing the next floor. A taller
        -- wall would contain the downward ray's start and be invisible to it.
        if vel.x ~= 0 then
            local wall = cast(pos.x, floor_y + step_up + clearance,
                next_x, floor_y + step_up + clearance)
            if SurfaceClassifier.is_wall_collision(wall) then
                vel.x, next_x = 0, pos.x
            end
        end
        local hit = cast(next_x, floor_y + step_up + clearance, next_x, floor_y - step_down)
        if SurfaceClassifier.is_ground_collision(hit)
            and hit.group ~= SurfaceClassifier.GROUPS.PLATFORM
            and hit.position.y > floor_y + step_up then
            -- A solid top in the skin-sized gap below the horizontal sweep is
            -- still too tall to climb. Block and recover the current support.
            vel.x, next_x = 0, pos.x
            hit = cast(next_x, floor_y + step_up + clearance, next_x, floor_y - step_down)
        end
        if SurfaceClassifier.is_ground_collision(hit)
            and hit.position.y <= floor_y + step_up
            and hit.position.y >= floor_y - step_down
            -- A one-way platform above the feet is never a step up.
            and (hit.group ~= SurfaceClassifier.GROUPS.PLATFORM or hit.position.y <= floor_y) then
            vel.y = (hit.position.y - floor_y) / dt
            self._vy = 0
            return true
        end
        self._airborne, self._vy = true, 0
    end
    self._vy = math.max((self._vy or 0) - M.gravity() * dt,
        -(defaults.max_fall_speed_tiles or 16) * tile_h)
    vel.y = self._vy
    local next_floor = floor_y + vel.y * dt
    -- Upward travel passes through one-way platforms. All landings sweep down
    -- to prevent tunnelling at high fall speeds.
    if vel.y <= 0 then
        local hit = cast(next_x, floor_y + clearance, next_x, next_floor)
        if SurfaceClassifier.is_ground_collision(hit) and hit.position.y <= floor_y + clearance then
            vel.y = (hit.position.y - floor_y) / dt
            self._vy, self._airborne, self._forced_airborne = 0, false, false
            return true
        end
    end
    if defaults.fall_out_kills ~= false and bounds and next_floor + clearance <= bounds.min_y + 16 then
        local below = cast(next_x, next_floor + clearance, next_x, next_floor - step_down)
        if not SurfaceClassifier.is_ground_collision(below) then return "fall_out" end
    end
    return true
end

function M.settle(self, raycast)
    if not self._grounded_movement or self._ignores_terrain then return end
    local defaults = RuntimeSettings.section("enemy_defaults", require "developer.config.enemy_defaults")
    local tile_h = tonumber(TileSettings.height or TileSettings.tile_height or TileSettings.size) or 64
    local pos = self.pos
    raycast = raycast or physics.raycast
    local hit = raycast(vmath.vector3(pos.x, pos.y, pos.z),
        vmath.vector3(pos.x, pos.y - (defaults.spawn_settle_depth_tiles or 8) * tile_h, pos.z),
        SurfaceClassifier.RAYCAST.GROUND)
    if not hit then return end
    local skin = Skins.skins[self.skin] or Skins.skins.default or {}
    pos.y = hit.position.y + (skin.feet or 40) * (self._body_scale or 1)
        + (defaults.ground_skin_px or 1)
    go.set_position(pos)
end

return M
