-- Actor sleep for streamed rooms (CP04b).
--
-- RoomManager hides a room by posting "disable" to every game object it
-- created, and shows it again with "enable". A message with no fragment
-- reaches every component, scripts included, but the engine keeps calling a
-- script's update while its game object is disabled. With its collision off,
-- an enemy in a hidden room would keep walking, and an opt-in falling enemy's
-- ground cast would miss so it fell out of the world. enemy.script hands both
-- messages to note(), and its update returns while self._room_asleep is set
-- (a death clip still finishes).
--
-- stream_settings.room.actor_sleep (default true) turns this off. It is read
-- through RuntimeSettings.section once per settings revision, so Game
-- Settings overrides arrive without a per-message copy of the section.

local StreamSettings = require "developer.config.stream_settings"

local M = {}

local cached_enabled, cached_revision

-- True when enemies in hidden rooms should sleep.
function M.enabled()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local revision = RuntimeSettings.revision and RuntimeSettings.revision()
    if revision == nil or cached_enabled == nil or cached_revision ~= revision then
        local section = RuntimeSettings.section("stream_settings", StreamSettings)
        local room = type(section) == "table" and section.room or nil
        cached_enabled = not (type(room) == "table" and room.actor_sleep == false)
        cached_revision = revision
    end
    return cached_enabled
end

-- Record a room "disable" or "enable" on an actor's script instance.
function M.note(self, message_id)
    if message_id == hash("disable") then
        self._room_asleep = M.enabled() or nil
    else
        if self._room_asleep then require("mvtk.enemies.decision_clock").reset(self) end
        self._room_asleep = nil
    end
end

-- Test hook: forget the cached setting.
function M._reset()
    cached_enabled, cached_revision = nil, nil
end

return M
