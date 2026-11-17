-- Message-only delivery; source text is rendered by the receiving GUI.
local C = require "mvtk.core.constants"
local Text = require "developer.config.reward_text"
local M = {}
function M.to_player(message_id, payload)
    if not C.URL.PLAYER then return false end
    return pcall(msg.post, C.URL.PLAYER, message_id, payload or {})
end
function M.notice(text, opts)
    if not text or text == "" then return false end
    return pcall(msg.post, "main:/toast_gui#toast", "toast", {
        text = text, duration = (opts and opts.duration) or Text.notice_duration,
    })
end
return M
