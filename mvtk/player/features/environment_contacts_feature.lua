local M = {id = "environment_contacts", order = 20,
    messages = {mvtk_env_push = "body", mvtk_env_lift = "body", mvtk_water_current = "body"}}

function M.on_message(self, message_id, message, sender)
    if message_id == hash("mvtk_water_current") then
        if self._is_dead and message.entering then return true end
        require("mvtk.player.surface_effects").note_water(self, sender, message)
        return true
    end
    local channel
    if message_id == hash("mvtk_env_push") then channel = "push"
    elseif message_id == hash("mvtk_env_lift") then channel = "lift"
    else return false end
    require("mvtk.player.surface_effects").note_contact(self, channel, sender, message)
    return true
end

function M.reset(self, reason)
    require("mvtk.player.surface_effects").clear_contacts(self)
end

return M
