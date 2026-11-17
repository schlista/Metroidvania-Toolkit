-- Plant horizontal input while aiming; motion/forces remain owned by physics.
local M = { id = "aim_stance", order = 42 }

function M.reset(self, reason)
    local state = self._host.features.aim_stance
    -- Cancel this stance's held press, not unrelated queued attacks.
    if state.active or state.released then
        self._ranged_buffer_count = math.max(0, (self._ranged_buffer_count or 0) - 1)
    end
    state.active, state.released, state.x, state.y, state.facing = false, false, nil, nil, nil
end

function M.pre_physics(self, dt, input)
    local state = self._host.features.aim_stance
    local aim = require("mvtk.combat.config").get().aim or {}
    local bomb = require("mvtk.core.util").require_config("developer.config.player_actions").bomb
    local bomb_press = bomb and (input.move_y or 0) <= -bomb.down_threshold
        and self._ability_can_use and self._ability_can_use("bomb")
    if not aim.stance or not self.grounded or self._compact_active
        or (self._stun_t or 0) > 0 or self._in_climb or self._on_wall
        or self._ledge_hanging or self._ledge_climbing or self._ledge_kinematic or bomb_press then
        -- Bomb actions run later and need the same queued press and Down input.
        if bomb_press then state.active, state.released = false, false end
        M.reset(self)
        return
    end
    if input.ranged_held then
        -- Read controller axes before frame-copy movement modifiers and climb filters.
        -- Never mutate that shared input: only the player's horizontal frame copy stops.
        local raw = require("mvtk.rooms.input_controller").input_state
        state.x, state.y = raw.move_x or 0, raw.move_y or 0
        state.active, state.released = true, false
        local intent = require("mvtk.player.combat_input").attack_intent(self,
            { move_x = state.x, move_y = state.y }, { aim = aim })
        if intent.aim_x ~= 0 then self.facing = intent.aim_x < 0 and -1 or 1 end
        state.facing = self.facing
        input.move_x = 0
    elseif state.active and input.ranged_up then
        state.active, state.released = false, true
    elseif state.active then
        -- Input blocking/disconnect can clear held without producing a release edge.
        M.reset(self)
    end
end

return M
