-- Opt-in acceptance contract for asynchronous Interact messages.
-- Registrants reporting outcomes set reports_result=true. Their handler returns
-- true only after accepting the press; false/nil refuses it. Existing feedback
-- stays in the handler. Unmarked legacy messages need no HUD acknowledgement.
-- The player supplies result_url; reporting never loads gameplay configuration.
local M = {}

function M.report(message, accepted)
    if accepted == "pending" then return end -- The receiving GUI/manager will decide.
    if message and message.interaction_result and message.result_url then
        msg.post(message.result_url, "hud_interact", {
            label = message.label, accepted = accepted == true,
        })
    end
end

-- Forward only the outcome fields, keeping nested GUI requests small.
function M.defer(message)
    if not (message and message.interaction_result and message.result_url) then return nil end
    return {interaction_result=true, result_url=message.result_url, label=message.label}
end

return M
