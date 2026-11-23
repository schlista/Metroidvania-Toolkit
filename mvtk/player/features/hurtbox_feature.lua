-- Publish to boss math hit tests after movement and form changes.
local Bounds = require "mvtk.player.collider_bounds"
local PlayerScale = require "mvtk.player.player_scale"
local M = {id = "hurtbox", order = 64}

local function publish(self)
    local state = self._host.features.hurtbox
    local Detection = require "mvtk.enemies.detection"
    Detection.set_player_grounded(self.grounded)
    Detection.set_player_velocity(self.vx or 0, self.vy or 0)
    if self._spine_physics_active then
        -- The enabled torso collider publishes after copying its pose.
        Detection.expect_collision_body()
        return
    end

    state.standing = state.standing or Bounds.rect("#co")
    local box = state.standing
    if self._compact_active then
        state.compact = state.compact or Bounds.rect("#co_compact")
        if state.compact then
            box = state.compact
        elseif box then
            -- The compact fixture may be unavailable during the component swap.
            local compact = self._cfg.compact_form or {}
            local half_h, center_y = PlayerScale.compact_hurtbox(
                box.half_h, box.y, compact.height_reduction_ratio)
            Detection.set_player_body(box.half_w, half_h, box.x, center_y)
            return
        end
    end
    if box then Detection.set_player_body(box.half_w, box.half_h, box.x, box.y) end
end

M.init = publish
M.post_physics = publish
M.actions = publish

function M.reset(self, reason)
    if reason == "final" then
        local Detection = require "mvtk.enemies.detection"
        Detection.set_player_body(nil)
        Detection.set_player_grounded(nil)
        Detection.set_player_velocity(nil, nil)
    else
        publish(self)
    end
end

return M
