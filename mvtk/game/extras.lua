-- Cross-save Extras unlocks: UI-free state shared by every save slot of this game.
-- Sources: profile section `unlocks` ({heard={[track]=true}, flags={[flag]=true},
-- cycle=n}) plus read-only `records.endings_seen` and `achievements.unlocked`.
-- No checkpoint provider: unlocks never belong to a slot.
local GameEvents = require "mvtk.core.game_events"
local M = {}
local SECTION = "unlocks"
local KINDS = { jukebox = "tracks", gallery = "entries" }
local state = nil
local config, config_revision = nil, nil
local watch, watch_revision = nil, nil

local function whole(n)
    return type(n) == "number" and n == n and n < math.huge and math.max(0, math.floor(n)) or 0
end
local function nonempty(value)
    return type(value) == "string" and value ~= ""
end
local function normalized(data)
    local out = { heard = {}, flags = {}, cycle = 0 }
    data = type(data) == "table" and data or {}
    for _, kind in ipairs({ "heard", "flags" }) do
        for id, value in pairs(type(data[kind]) == "table" and data[kind] or {}) do
            if nonempty(id) and value == true then out[kind][id] = true end
        end
    end
    out.cycle = whole(data.cycle)
    return out
end
local function profile()
    return require "mvtk.core.profile_store"
end
local function sandboxed()
    return require("mvtk.core.checkpoint").is_save_sandboxed()
end
local function load()
    if not state then state = normalized(profile().get(SECTION)) end
    return state
end

-- Hub events reach the listener while Extras is off: read once per settings revision.
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if config == nil or config_revision ~= revision then
        config, config_revision = Runtime.section("extras", require "developer.config.extras"), revision
    end
    return config
end

local function section_rows(cfg, kind)
    local section = type(cfg[kind]) == "table" and cfg[kind] or {}
    local list = section[KINDS[kind]]
    return section.enabled ~= false and type(list) == "table" and list or {}
end
local function unlock_of(kind, row)
    if type(row.unlock) == "table" then return row.unlock end
    return { type = kind == "jukebox" and "heard" or "always" }
end
local function row_id(kind, row)
    if kind == "jukebox" then return row.track end
    return row.id
end

-- Flags that unlock an entry of an enabled section, rebuilt per settings revision.
local function watched()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if watch == nil or watch_revision ~= revision then
        watch = {}
        local cfg = M.settings()
        if cfg.enabled == true then
            for _, kind in ipairs({ "jukebox", "gallery" }) do
                for _, row in ipairs(section_rows(cfg, kind)) do
                    local unlock = type(row) == "table" and unlock_of(kind, row) or {}
                    if unlock.type == "flag" and nonempty(unlock.flag) and nonempty(row_id(kind, row)) then
                        watch[unlock.flag] = watch[unlock.flag] or {}
                        local list = watch[unlock.flag]
                        list[#list + 1] = { kind = kind, id = row_id(kind, row), title = row.title }
                    end
                end
            end
        end
        watch_revision = revision
    end
    return watch
end

-- Read-only sources, gathered once per query so a list costs three profile reads.
local function sources()
    local records = profile().get("records")
    local achievements = profile().get("achievements")
    return { unlocks = load(),
        endings = type(records.endings_seen) == "table" and records.endings_seen or {},
        achievements = type(achievements.unlocked) == "table" and achievements.unlocked or {} }
end

-- unlock: one entry's `unlock` table; track: the jukebox track id for "heard".
function M.is_unlocked(unlock, track, src)
    if type(unlock) ~= "table" then return false end
    src = src or sources()
    local kind = unlock.type
    if kind == "always" then return true end
    if kind == "heard" then return nonempty(track) and src.unlocks.heard[track] == true end
    if kind == "flag" then return nonempty(unlock.flag) and src.unlocks.flags[unlock.flag] == true end
    if kind == "cycle" then return src.unlocks.cycle >= math.max(1, whole(unlock.cycle)) end
    if kind == "achievement" then return nonempty(unlock.id) and src.achievements[unlock.id] ~= nil end
    if kind == "ending" then
        if nonempty(unlock.ending_id) then return src.endings[unlock.ending_id] == true end
        return next(src.endings) ~= nil
    end
    return false
end

local function credits_rows(cfg, src)
    if type(cfg.credits) ~= "table" or cfg.credits.enabled == false then return {} end
    local Endings = require "mvtk.game.endings"
    local ending_cfg = require("developer.config.runtime_settings").section(
        "game_completion", require "developer.config.game_completion")
    local out = {}
    for _, ending in ipairs(Endings.list(ending_cfg)) do
        if nonempty(ending.id) and src.endings[ending.id] == true then
            out[#out + 1] = { id = ending.id, title = ending.title, unlocked = true }
        end
    end
    return out
end

-- Rows of "jukebox", "gallery" or "credits" in authored order. Each row has id,
-- title and unlocked; locked rows are left out while show_locked is false.
-- Ids are for lookups and saves only; they are never player-visible text.
function M.rows(kind)
    local cfg = M.settings()
    local src = sources()
    if kind == "credits" then return credits_rows(cfg, src) end
    if not KINDS[kind] then return {} end
    local out = {}
    for _, row in ipairs(section_rows(cfg, kind)) do
        local id = type(row) == "table" and row_id(kind, row)
        if nonempty(id) then
            local unlocked = M.is_unlocked(unlock_of(kind, row), row.track, src)
            if unlocked or cfg.show_locked ~= false then
                out[#out + 1] = { id = id, track = row.track, image = row.image, title = row.title,
                    caption = row.caption, unlocked = unlocked }
            end
        end
    end
    return out
end

-- True when Extras is on and any enabled section has an unlocked row.
function M.any_unlocked()
    if M.settings().enabled ~= true then return false end
    for _, kind in ipairs({ "credits", "jukebox", "gallery" }) do
        for _, row in ipairs(M.rows(kind)) do
            if row.unlocked then return true end
        end
    end
    return false
end

local function writable()
    return M.settings().enabled == true and not sandboxed()
end

-- Called when a music track starts playing. The 10-second profile throttle
-- bounds the write; GameManager.final forces it at shutdown.
function M.note_track(id)
    if not nonempty(id) or not writable() then return false end
    load()
    if state.heard[id] then return false end
    state.heard[id] = true
    local Profile = profile()
    Profile.put(SECTION, normalized(state))
    Profile.flush(false)
    return true
end

-- Persist before announcing; a refused write leaves no notice and is retried
-- by the next session's scan.
local function record_flag(flag, entries, cfg)
    load()
    if state.flags[flag] then return false end
    state.flags[flag] = true
    local Profile = profile()
    Profile.put(SECTION, normalized(state))
    if not Profile.flush(true) then
        state.flags[flag] = nil
        Profile.put(SECTION, normalized(state))
        return false
    end
    if cfg.notify == true then
        local Notices = require "mvtk.ui.notices"
        for _, entry in ipairs(entries) do
            Notices.post({ kind = "extra", key = "extra_" .. entry.id,
                title = { key = "notice.extra_unlocked" }, text = entry.title or "" })
        end
    end
    return true
end

-- Content added after a save still unlocks: scan watched flags and record the
-- New Game+ cycle. Silent.
function M.on_session_start()
    if not writable() then return end
    load()
    local changed = false
    local Flags = require "mvtk.core.flags"
    for flag in pairs(watched()) do
        if not state.flags[flag] and Flags.has(flag) then
            state.flags[flag] = true
            changed = true
        end
    end
    local cycle = whole(require("mvtk.game.new_game_plus").cycle())
    if cycle > state.cycle then
        state.cycle = cycle
        changed = true
    end
    if changed then
        local Profile = profile()
        Profile.put(SECTION, normalized(state))
        Profile.flush(true)
    end
end

GameEvents.on("flag_set", function(event)
    local flag = type(event) == "table" and event.flag
    if not nonempty(flag) or event.value == false then return end
    local entries = watched()[flag]
    if not entries or not writable() then return end
    record_flag(flag, entries, M.settings())
end)

return M
