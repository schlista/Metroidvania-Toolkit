-- Keep baked actors in their room collection while their defeat rule holds.
local M = {}

function M.enter(self)
    local Util = require "mvtk.core.util"
    Util.post_component_enabled("#sprite", false)
    Util.post_component_enabled("#co", false)
    if Util.actor_probe then Util.actor_probe(nil, go.get_id()) end
    self._dormant = true
    self.spawn_id = nil
    require("mvtk.enemies.enemy_defeats").register_dormant(
        self.defeat_key, msg.url("."), self._room_id or self.room_id, self)
end

return M
