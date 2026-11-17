-- Contact-grace state for the player's pushable-block grab.
-- Collision callbacks own timer refresh; this module only ages and releases it.

local M = {}

function M.clear(self)
    require("mvtk.player.hold_toggles").clear(self, "grab")
    self._block_grab = nil
    self._block_grab_contact_t = 0
    self._block_grab_motion = nil
end

function M.wants_hold(self, input)
    local toggles = require "mvtk.player.hold_toggles"
    toggles.sync(self)
    if not toggles.enabled("grab") then return self._interact_held == true end
    -- player.script checks the grab three times on this shared frame copy.
    -- It empties the copy next frame, so this marker never consumes a later press.
    if input and input.interact_down and not input._grab_toggle_processed then
        input._grab_toggle_processed = true
        toggles.set(self, "grab", not toggles.get(self, "grab"))
    end
    return toggles.get(self, "grab")
end

function M.update(self, dt, can_hold)
    if not can_hold then require("mvtk.player.hold_toggles").clear(self, "grab") end
    if dt and (self._block_grab_contact_t or 0) > 0 then
        self._block_grab_contact_t = math.max(0, (self._block_grab_contact_t or 0) - dt)
    end

    if self._block_grab
        and (not can_hold or (self._block_grab_contact_t or 0) <= 0) then
        M.clear(self)
        return true
    end
    return false
end

return M

