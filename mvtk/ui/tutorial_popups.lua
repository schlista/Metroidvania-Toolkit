-- mvtk/ui/tutorial_popups.lua
-- Config-driven tutorial popup dispatcher.

local FlagsOk, Flags = pcall(require, "mvtk.core.flags")
-- Literal require: Bob registers the config with this module, so it exists
-- when the boot GUI first loads us (AUDIT_BUILD_BUNDLING row 1).
local Config = require "developer.config.tutorial_popups"
local C = require "mvtk.core.constants"

local popups = {}
local shown = {}

local function load()
    if type(Config) == "table" and type(Config.popups) == "table" then
        popups = Config.popups
    end
end

load()

local M = {}

function M.reset()
    shown = {}
end

function M.on_event(event_name)
    for id, def in pairs(popups) do
        local matches_event = def.condition and def.condition.event == event_name
        local already_shown = def.trigger_flag and FlagsOk and Flags.get and Flags.get(def.trigger_flag)
        if matches_event and not already_shown then
            local title = def.title
            local body = def.body
            local hud = C.url and C.url("MODE_HUD")
            if hud then pcall(msg.post, hud, "show_tutorial", { id = id, title = title, description = body, title_key = def.title_key, body_key = def.body_key, position = def.position or "top" }) end
            shown[id] = true
            if def.trigger_flag and FlagsOk and Flags.set then
                pcall(Flags.set, def.trigger_flag, true)
            end
        end
    end
end

return M
