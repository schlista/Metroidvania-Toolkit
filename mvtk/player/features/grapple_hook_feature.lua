-- Advance hook travel before ordinary movement and choose the optional let-go pose.
local M = { id = "grapple_hook", order = 31, movement_anims = {"grapple_release"} }

function M.pre_physics(self, dt, input)
    local PSTATE = require "mvtk.player.player_state"
    if PSTATE.advance_grapple_hook(self, dt, input) == "caught" then
        require("mvtk.player.player_combat").grapple_caught(self)
    end
end

function M.anim_state(self, state)
    if self._grapple_active or (self._grapple_carry_t or 0) <= 0
        or self._grapple_release_kind ~= "let_go"
        or (state ~= "jump" and state ~= "fall") then return nil end
    if self._anim_is_spine then
        if require("developer.config.player_spine_map").grapple_release ~= nil then
            return "grapple_release"
        end
    else
        -- The player controller has no atlas property. Ask the Player art import
        -- destination explicitly; a missing flipbook does not raise an error.
        local AnimIndex = require "mvtk.core.anim_index"
        if AnimIndex.has("/developer/assets/atlas/player.atlas", "grapple_release") == true then
            return "grapple_release"
        end
    end
end

function M.reset(self)
    self._grapple_hook = nil
end

return M
