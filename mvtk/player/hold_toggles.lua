-- Player-owned press-instead-of-hold state. Physical input is never rewritten.
local M = {}
local cached, cached_revision

local function config()
    local runtime = require "developer.config.runtime_settings"
    local revision = runtime.revision()
    if not cached or cached_revision ~= revision then
        cached = {
            accessibility = runtime.section("accessibility", require "developer.config.accessibility"),
            player = runtime.get_player_settings_base(),
            healing = runtime.section("healing", require "developer.config.healing"),
        }
        cached_revision = revision
    end
    return cached
end

-- Availability describes the game, not the current save's unlocked abilities.
function M.available(id)
    local cfg = config()
    if id == "grab" then return (cfg.player.block_grab or {}).enabled == true end
    if id == "grapple" then
        local definition = require("developer.config.abilities").abilities.grapple
        return definition ~= nil and definition.enabled ~= false
            and not (cfg.player.grapple or {}).stay_hooked
    end
    if id == "heal" then return cfg.healing.model == "channel" end
    if id == "run" then
        local definition = require("developer.config.abilities").abilities.dash
        return (cfg.player.slide_to_run or {}).enabled == true
            or (definition ~= nil and definition.enabled ~= false)
    end
    if id == "glide" then
        local definition = require("developer.config.abilities").abilities.glide
        return definition ~= nil and definition.enabled ~= false
    end
    if id == "aim" then return (require("mvtk.combat.config").get().aim or {}).stance == true end
    return false
end

function M.enabled(id)
    local cfg = config().accessibility
    if (cfg.show or {}).toggles ~= false and M.available(id) then
        local value = require("mvtk.core.settings").get("accessibility.toggles." .. id)
        if type(value) == "boolean" then return value end
    end
    return (cfg.toggles or {})[id] == true
end

function M.clear_all(self)
    self._hold_latch = nil
    self._light_hold_t = 0
    self._light_charge_t, self._light_charge_release_t = nil, nil
end

-- Each consumer has its own cursor: grab may synchronize before grapple/heal.
-- A whole menu-open/close interval must be observed even with no paused frames.
function M.sync(self, id)
    local input = require "mvtk.rooms.input_controller"
    local generation = input.block_generation()
    local blocked = input.get_blocked()
    local changed = self._hold_generation ~= nil and self._hold_generation ~= generation
    if changed or blocked then M.clear_all(self) end
    self._hold_generation = generation
    if id then
        self._hold_seen = self._hold_seen or {}
        local previous = self._hold_seen[id]
        self._hold_seen[id] = generation
        return blocked or (previous ~= nil and previous ~= generation)
    end
    return blocked or changed
end

function M.get(self, id)
    M.sync(self)
    return self._hold_latch ~= nil and self._hold_latch[id] == true
end

function M.set(self, id, value)
    if M.sync(self) and require("mvtk.rooms.input_controller").get_blocked() then return false end
    self._hold_latch = self._hold_latch or {}
    self._hold_latch[id] = value == true
    return self._hold_latch[id]
end

function M.clear(self, id)
    if self._hold_latch then self._hold_latch[id] = nil end
end

return M
