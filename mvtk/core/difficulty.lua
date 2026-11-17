-- mvtk/core/difficulty.lua
-- Central difficulty profile loader and helpers.

local Multipliers = require "mvtk.combat.multipliers"
local Checkpoint = require "mvtk.core.checkpoint"
local PauseModel = require "mvtk.ui.pause_menu_model"

local M = {}

local current, cached, cached_revision

function M.settings()
    local RuntimeSettings = require "developer.config.runtime_settings"
    local revision = RuntimeSettings.revision()
    if not cached or cached_revision ~= revision then
        cached = RuntimeSettings.section("difficulty", require "developer.config.difficulty_settings")
        cached_revision = revision
    end
    return cached
end

function M.default_profile()
    local cfg = M.settings()
    local profiles = cfg.profiles or {}
    if profiles[cfg.current] then return cfg.current end
    local authored = require "developer.config.difficulty_settings"
    if profiles[authored.current] then return authored.current end
    if profiles.normal then return "normal" end
    local keys = {}; for id in pairs(profiles) do keys[#keys + 1] = id end
    table.sort(keys)
    return keys[1]
end

function M.selection_mode()
    local mode = M.settings().selection
    return (mode == "fixed" or mode == "anytime") and mode or "new_game"
end

function M.list()
    local cfg, rows = M.settings(), {}
    for _, id in ipairs(cfg.order or {}) do
        local profile = (cfg.profiles or {})[id]
        if profile then rows[#rows + 1] = { id = id, label = type(profile.label) == "string" and profile.label:find("%S") and profile.label or { key = "list.missing_name" },
            description = profile.description or "" } end
    end
    return rows
end

function M.set(name)
    if M.selection_mode() == "fixed" then name = M.default_profile() end
    if (M.settings().profiles or {})[name] then
        current = name
        return true
    end
    return false
end

function M.get()
    local profiles = M.settings().profiles or {}
    if M.selection_mode() == "fixed" or not profiles[current] then current = M.default_profile() end
    return current, profiles[current] or {}
end

function M.defaults() current = M.default_profile() end

Checkpoint.register_provider("difficulty", {
    version = 1, order = 15,
    capture = function() return { profile = M.get() } end,
    apply = function(data)
        M.defaults()
        if type(data) == "table" and type(data.profile) == "string" then M.set(data.profile) end
    end,
    defaults = M.defaults,
})

PauseModel.register_entry("difficulty", {
    after = "fast_travel",
    visible = function() return M.selection_mode() == "anytime" end,
    label = function()
        local _, profile = M.get()
        return { key = "pause.difficulty", params = { name = type(profile.label) == "string" and profile.label:find("%S")
            and { text = profile.label } or { key = "list.missing_name" } } }
    end,
    run = function()
        local previous, rows = M.get(), M.list()
        local next_index = 1
        for i, row in ipairs(rows) do if row.id == previous then next_index = i % #rows + 1; break end end
        if rows[next_index] then
            M.set(rows[next_index].id)
            local ok, err = Checkpoint.save_provider_updates({ difficulty = { profile = M.get() } })
            if not ok then
                M.set(previous)
                print("[DIFFICULTY] Cannot save selection: " .. tostring(err))
            end
        end
        return { close = false }
    end,
})

-- These getters expose only the active profile's own values.
function M.damage_taken_mult()
    local _, p = M.get()
    return p.damage_taken_mult or 1.0
end

function M.damage_dealt_mult()
    local _, p = M.get()
    return p.damage_dealt_mult or 1.0
end

function M.enemy_health_mult()
    local _, p = M.get()
    return p.enemy_health_mult or 1.0
end

function M.loot_mult()
    local _, p = M.get()
    return p.loot_mult or 1.0
end

M.MULTIPLIER_SOURCE = {
    id = "difficulty", order = 10, challenge = true, range = { 0.1, 10 },
    factor = function(channel)
        local _, profile = M.get()
        return Multipliers.table_factor(profile, channel)
    end,
}

function M.get_multiplier()
    return Multipliers.challenge_rating()
end

return M
