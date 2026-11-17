-- Bomb placement runs in the player context so outgoing damage is scaled once.
local M = {}

function M.request(self, input)
    local cfg = require("mvtk.core.util").require_config("developer.config.player_actions").bomb
    if not cfg or not input or not self.grounded or (self._ranged_buffer_count or 0) <= 0 then return false end
    if (input.move_y or 0) > -cfg.down_threshold and not self._compact_active then return false end
    local state = self._host.features.bomb
    local live = {}
    for _, id in ipairs(state.live or {}) do if go.exists(id) then live[#live + 1] = id end end
    state.live = live
    if #live >= cfg.max_active or not self._ability_can_use("bomb") then return false end
    local tile = require("mvtk.core.util").require_config("developer.config.tile_settings")
    local pos = self.pos or go.get_position()
    local id = factory.create(require("mvtk.core.constants").URL.FACTORY.bomb,
        vmath.vector3(pos.x, pos.y - (self.collider_half_height or 0), pos.z), nil, {
            fuse = cfg.fuse_time, radius = cfg.radius_tiles * tile.width,
            damage = require("mvtk.player.player_stats").outgoing_damage(cfg.damage),
            knockback = cfg.knockback_px, attack_type = cfg.action_tag, owner = msg.url(),
        })
    if not id then return false end
    live[#live + 1] = id
    self._ranged_buffer_count = self._ranged_buffer_count - 1
    self._ability_use("bomb")
    if cfg.sound_place ~= "" then require("mvtk.audio.audio").sfx(cfg.sound_place) end
    return true
end

function M.reset(self)
    local state = self._host.features.bomb
    for _, id in ipairs(state.live or {}) do if go.exists(id) then go.delete(id) end end
    state.live = {}
end

return M
