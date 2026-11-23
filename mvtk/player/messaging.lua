-- mvtk/player/messaging.lua
-- Focused player message handlers used by player.script.

local SurfaceEffects = require "mvtk.player.surface_effects"
local PlayerResources = require "mvtk.player.resources"
local PlayerHost = require "mvtk.player.player_host"
local PlayerStats = require "mvtk.player.player_stats"

local M = {}

function M.handle_environment_message(self, message_id, message, sender, sync_player_position)
  if message_id == hash("enter_climb_zone") then
    require("mvtk.player.movement").enter_climb_zone(self, message)
    return true
  end
  if message_id == hash("exit_climb_zone") then
    require("mvtk.player.movement").exit_climb_zone(self, message)
    return true
  end
  if message_id == hash("mvtk_player_modifier") then
    if message and (message.layer == nil or message.layer == "temporary")
      and (not PlayerStats.has_source(message.source) or PlayerStats.has_source(message.source, "temporary")) then
      PlayerStats.set_source(message.source, message.values, { layer = "temporary",
        duration = message.duration, lease = message.lease, group = message.group })
    end
    return true
  end
  if message_id == hash("mvtk_player_modifier_clear") then
    if message and PlayerStats.has_source(message.source, "temporary") then PlayerStats.clear_source(message.source) end
    return true
  end
  if message_id == hash("mvtk_stat_gain_feedback") then
    PlayerResources.post_resource_float(-(message.amount or 0), "upgrade")
    return true
  end

  if message_id == hash("apply_movement_modifier") then
    local id = message and (message.id or "movement")
    local mult = tonumber(message and message.multiplier) or 1.0
    self._movement_modifiers = self._movement_modifiers or {}
    self._movement_modifiers[tostring(id)] = mult
    return true
  end

  if message_id == hash("remove_movement_modifier") then
    local id = message and (message.id or "movement")
    if self._movement_modifiers then
      self._movement_modifiers[tostring(id)] = nil
    end
    return true
  end

  if message_id == hash("external_force") then
    if message and message.conveyor then
      SurfaceEffects.note_conveyor(self, sender, message.vx or 0, message.vy or 0, message.overlap)
      SurfaceEffects.sum_conveyor_forces(self)
    else
      self._ext_fx = (self._ext_fx or 0) + (message and (message.vx or 0) or 0)
      self._ext_fy = (self._ext_fy or 0) + (message and (message.vy or 0) or 0)
    end
    return true
  end

  if message_id == hash("apply_external_force") then
    -- Custom triggers can send a velocity vector or legacy scalar components.
    local force = message and message.force
    self._ext_fx = (self._ext_fx or 0) + (force and force.x or (message and message.vx) or 0)
    self._ext_fy = (self._ext_fy or 0) + (force and force.y or (message and message.vy) or 0)
    return true
  end

  if message_id == hash("on_conveyor") then
    local dir = message and message.direction
    local speed = message and message.speed
    local vx, vy = SurfaceEffects.conveyor_vector(dir, speed)
    SurfaceEffects.note_conveyor(self, sender, vx, vy, message and message.overlap)
    SurfaceEffects.sum_conveyor_forces(self)
    return true
  end

  if message_id == hash("off_conveyor") then
    SurfaceEffects.end_conveyor(self, sender, message and message.grace)
    SurfaceEffects.sum_conveyor_forces(self)
    return true
  end

  if message_id == hash("platform_delta") then
    local dx = message and (message.dx or 0) or 0
    local dy = message and (message.dy or 0) or 0
    self._platform_delta_x = (self._platform_delta_x or 0) + dx
    self._platform_delta_y = (self._platform_delta_y or 0) + dy
    if dx ~= 0 or dy ~= 0 then
      self.pos.x = (self.pos.x or 0) + dx
      self.pos.y = (self.pos.y or 0) + dy
      if sync_player_position then
        sync_player_position(self)
      end
    end
    return true
  end

  return PlayerHost.on_message(self, message_id, message, sender)
end

function M.reset_features(self, reason)
  PlayerHost.reset(self, reason)
end

function M.on_restore(self, message)
  PlayerHost.restore(self, message)
end

return M
