-- Authored stand points name the collider's bottom; recorded positions name
-- the player origin. Only this boundary converts between those coordinate kinds.
local M = {}
local waiting = {}

local function body_bottom(component)
    local body = assert(b2d.get_body(component), "Player placement needs its live collision body")
    local bottom
    -- Box2D 2's get_shape returns the original polygon vertices in pixels,
    -- including resource offsets and baked player scale, without AABB skin.
    -- Reading the body also handles a side/alternate resource on the component.
    for _, fixture in ipairs(b2d.body.get_fixtures(body)) do
        local shape = b2d.fixture.get_shape(body, fixture.index)
        if shape.vertices then
            for _, vertex in ipairs(shape.vertices) do
                bottom = math.min(bottom or math.huge, vertex.y)
            end
        elseif shape.center and shape.radius then
            bottom = math.min(bottom or math.huge, shape.center.y - shape.radius)
        end
    end
    assert(bottom, "Player placement needs a polygon or circle collision shape")
    return bottom
end

function M.feet_to_origin(self)
    if self._spine_physics_active then
        local game = require("developer.config.resolved_config").player.spine_physics or {}
        local settings = require("developer.config.runtime_settings").get_player_settings().spine_physics or {}
        local bones = require "mvtk.animation.bone_collision"
        local spine_url = require("mvtk.player.spine_visual").resolve()
        go.update_world_transform()
        local root_y = go.get_world_position().y
        local bottom
        for _, part in ipairs({"foot_l", "foot_r"}) do
            if (game.enable_parts or {})[part] ~= false then
                local name = (settings.bone_map or {})[part] or (game.bone_map or {})[part]
                local position = name and bones.get_bone_position(spine_url, name)
                -- The model's bone GOs may not exist during root init. Hold
                -- startup and keep its bone colliders disabled until they do.
                if not position then return nil end
                local component = msg.url(nil, go.get_id(part), "collisionobject")
                bottom = math.min(bottom or math.huge, position.y - root_y + body_bottom(component))
            end
        end
        assert(bottom, "Player placement needs an enabled foot collider")
        return -bottom
    end
    return -body_bottom(self._compact_active and "#co_compact" or "#co")
end

function M.origin(self, point, position_kind)
    local lift = position_kind == "feet" and assert(M.feet_to_origin(self), "Player foot bones are not ready") or 0
    return vmath.vector3(point.x, point.y + lift, self.pos and self.pos.z or point.z or 0)
end

function M.start(self, point)
    if self._spine_physics_active and not M.feet_to_origin(self) then
        self._placement_start_point = vmath.vector3(point)
        waiting[go.get_id()] = true
        return vmath.vector3(point)
    end
    return M.origin(self, point, "feet")
end

function M.resume_start(self)
    if not M.feet_to_origin(self) then
        self._placement_retries = (self._placement_retries or 0) + 1
        local physics = require("developer.config.resolved_config").player.spine_physics or {}
        assert(self._placement_retries < (tonumber(physics.bone_resolve_max_retries) or 30),
            "Player placement could not resolve its configured foot bones")
        return false
    end
    self.pos = M.origin(self, self._placement_start_point, "feet")
    go.set_position(self.pos)
    M.cancel_start(self)
    return true
end

function M.cancel_start(self)
    if not self._placement_start_point then return end
    waiting[go.get_id()] = nil
    self._placement_start_point = nil
    self._placement_retries = nil
end

function M.is_waiting(player_url)
    return waiting[player_url.path] == true
end

return M
