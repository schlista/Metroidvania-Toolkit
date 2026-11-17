-- Rewrite only the player's frame copy; raw input and menu controls stay physical.
local Hold = require "mvtk.player.hold_toggles"
local M = { id = "hold_toggle", order = 4 }

local function glide_allowed(self)
    return not self.grounded and not self._in_water and not self._in_climb
        and not self._grapple_active and not self._on_wall
        and not self._ledge_hanging and not self._ledge_climbing and not self._ledge_kinematic
        and (self._cfg.glide or {}).enabled == true
end

local function sliding(self)
    return (self._slide_t or 0) > 0 or (self._slide_recovery_t or 0) > 0
end

local function neutral(self, input)
    return math.abs(input.move_x or 0) <= (self._cfg.walk_stop_deadzone or 0.2)
end

local function aim_allowed(self, input)
    local aim = require("mvtk.combat.config").get().aim or {}
    local bomb = require("mvtk.core.util").require_config("developer.config.player_actions").bomb
    local bomb_press = bomb and (input.move_y or 0) <= -bomb.down_threshold
        and self._ability_can_use and self._ability_can_use("bomb")
    return aim.stance and self.grounded and not self._compact_active
        and (self._stun_t or 0) <= 0 and not self._in_climb and not self._on_wall
        and not self._ledge_hanging and not self._ledge_climbing and not self._ledge_kinematic
        and not bomb_press
end

function M.reset(self, reason)
    Hold.clear_all(self)
    local state = self._host.features.hold_toggle
    state.glide_candidate, state.extra_jumps, state.slide_active = nil, nil, nil
end

function M.pre_physics(self, dt, input)
    local state = self._host.features.hold_toggle
    state.glide_candidate = nil
    -- A separate consumer cursor observes even a complete pause between updates,
    -- after another consumer has synchronized the shared latch table.
    if Hold.sync(self, M.id) then
        M.reset(self, "blocked")
        input.jump_held, input.slide_held, input.ranged_held = false, false, false
        input.ranged_down, input.ranged_up = false, false
        return
    end

    if not Hold.enabled("glide") or not glide_allowed(self) then
        Hold.clear(self, "glide")
    elseif input.jump_down then
        if Hold.get(self, "glide") then
            Hold.clear(self, "glide")
            if (self.vy or 0) < 0 then input.jump_held = false end
        elseif (self.vy or 0) < 0 then
            -- on_input already spent ordinary air jumps (and made vy positive).
            -- Confirm update-time jumps after physics before committing the latch.
            state.glide_candidate, state.extra_jumps = true, self._extra_jumps or 0
        end
    end
    if Hold.get(self, "glide") and (self.vy or 0) < 0 then input.jump_held = true end

    if not Hold.enabled("run") or not (self._cfg.slide_to_run or {}).enabled then
        Hold.clear(self, "run")
    else
        if input.slide_down then
            if not Hold.get(self, "run") then Hold.set(self, "run", true)
            elseif state.slide_active == false then
                -- on_input may already have started the next slide. The prior
                -- post hook records whether the previous slide had finished.
                Hold.clear(self, "run")
                input.slide_held = false
            end
        end
        if Hold.get(self, "run") then
            -- Withhold the synthetic hold after sliding at neutral, so physics
            -- can clear its run gate (including its configured deceleration).
            input.slide_held = sliding(self) or not neutral(self, input)
        end
    end

    if not Hold.enabled("aim") or not aim_allowed(self, input) then
        Hold.clear(self, "aim")
    else
        if input.ranged_down then
            if Hold.get(self, "aim") then
                Hold.clear(self, "aim")
                input.ranged_down, input.ranged_up = false, true
                -- The release tap was queued before this hook. Keep the original
                -- stance shot, discarding only the second press's extra shot.
                self._ranged_buffer_count = math.max(0, (self._ranged_buffer_count or 0) - 1)
            else Hold.set(self, "aim", true) end
        end
        input.ranged_held = Hold.get(self, "aim")
        if input.ranged_held then input.ranged_up = false end
    end
end

function M.post_physics(self, dt, input, collision)
    local state = self._host.features.hold_toggle
    if not glide_allowed(self) then Hold.clear(self, "glide")
    elseif state.glide_candidate and (self.vy or 0) < 0
        and (self._extra_jumps or 0) == state.extra_jumps then
        Hold.set(self, "glide", true)
    end
    state.glide_candidate, state.extra_jumps = nil, nil
    state.slide_active = sliding(self)
    if not state.slide_active and neutral(self, input) and not self._run_gate then
        Hold.clear(self, "run")
    end
    if not aim_allowed(self, input) then Hold.clear(self, "aim") end
end

return M
