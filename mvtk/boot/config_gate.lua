-- mvtk/boot/config_gate.lua
-- Configuration check that runs before the game collection loads.
--
-- An error raised in a script's init only fails that one script: the
-- collection proxy ignores the result and every other object still starts.
-- The boot host therefore asks this gate before loading the game proxy, and
-- shows the start screen's blocked message instead of a half-started session.
-- The detail stays in the console; the player sees one ui_text line.

-- This runs on the boot screen, before the game collection registers its
-- modules, and validation loads each config by name. Reaching build_deps
-- literally puts every config in the boot host's module closure.
require "mvtk.core.build_deps"

local M = {}

-- The start-screen text shown while configuration errors block Play Game.
M.MESSAGE_KEY = "start.config_blocked"

local result_ok = nil
local result_revision = nil

local function settings_revision()
    return require("developer.config.runtime_settings").revision()
end

local function validate()
    local Debug = require "developer.config.debug_config"
    local ConfigValidator = require "mvtk.core.config_validator"
    local ok, valid
    if Debug and Debug.global and Debug.global.enable then
        -- Full validation prints every error box (debug builds).
        ok, valid = pcall(ConfigValidator.validate_all_configs)
    else
        -- Quick validation prints the first failing file (release builds).
        ok, valid = pcall(ConfigValidator.validate_quick)
    end
    if not ok then
        print("[CONFIG_GATE] Validation raised an error: " .. tostring(valid))
        return false
    end
    return valid == true
end

--- True when the configuration may start a game session. The result is kept
--- until Game Settings changes the runtime settings revision.
function M.check()
    local revision = settings_revision()
    if result_ok == nil or result_revision ~= revision then
        result_ok = validate()
        result_revision = revision
        if not result_ok then
            print("[CONFIG_GATE] Game start blocked: fix the configuration errors listed above,"
                .. " then Build again.")
        end
    end
    return result_ok
end

--- Forget the cached result (tests and editor hot reload).
function M.reset()
    result_ok, result_revision = nil, nil
end

return M
