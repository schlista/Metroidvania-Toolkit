-- Run-local counters and in-game time. Safe for GameManager's headless loaders:
-- only GameEvents is required at load; bootstrap explicitly registers storage.
local GameEvents = require "mvtk.core.game_events"
-- Not a literal require: a module requiring itself is a cycle, and Bob refuses require cycles.
local SELF_MODULE = "mvtk.game.run_stats"
local M = {}
local fields = {"playtime_s", "deaths", "enemies_defeated", "bosses_defeated",
    "collectibles_found", "secrets_found", "rooms_visited", "quests_completed"}
local function whole(n)
    return type(n) == "number" and n == n and n < math.huge and math.max(0, math.floor(n)) or 0
end
local function normalized(data)
    local out = {}
    for _, key in ipairs(fields) do out[key] = whole(type(data) == "table" and data[key]) end
    return out
end
local state = normalized(nil)
local pending
local hud_revision, hud_visible, hud_second
local function timer_visible()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if hud_revision ~= revision then
        local layout = Runtime.section("hud_layout", require "developer.config.hud_layout")
        local entry = require("mvtk.ui.hud_layout").entry(layout, "play_timer", (Runtime.load() or {}).hud_layout)
        hud_visible = entry.enabled ~= false and entry.visible == true
        hud_revision = revision
    end
    return hud_visible
end
local function post_timer(seconds)
    if timer_visible() then require("mvtk.ui.hud_bus").post("play_timer", {seconds = seconds}) end
end

function M.snapshot() return normalized(state) end
function M.playtime_s() return whole(state.playtime_s) end
function M.tick(dt, counting)
    if counting and type(dt) == "number" and dt > 0 and dt < math.huge then
        state.playtime_s = state.playtime_s + dt
        local seconds = M.playtime_s()
        -- Cache merged visibility even on frames with no whole-second change.
        local visible = timer_visible()
        if seconds ~= hud_second then
            hud_second = seconds
            if visible then require("mvtk.ui.hud_bus").post("play_timer", {seconds = seconds}) end
        end
    end
end
-- Read overrides at Records/event time, never every frame.
function M.settings()
    return require("developer.config.runtime_settings").section("run_stats", require "developer.config.run_stats")
end

function M.time_section()
    return {id = "time", order = 10,
        header = function() return {key = "journal.time"} end,
        lines = function()
            local lines = {{label = {key = "journal.play_time"}, value = require("mvtk.ui.time_text").playtime(
                require(SELF_MODULE).playtime_s())}}
            if require("mvtk.player.assist").record_use() and require("mvtk.core.flags").has("assist_used") then
                lines[#lines + 1] = {label = {key = "records.assist_used"}, value = ""}
            end
            return lines
        end}
end
function M.statistics_section()
    return {id = "statistics", order = 60,
        header = function() return {key = "journal.statistics"} end,
        visible = function() return require(SELF_MODULE).settings().show_in_records == true end,
        lines = function()
            local stats, out = require(SELF_MODULE).snapshot(), {}
            for _, key in ipairs({"deaths", "enemies_defeated", "bosses_defeated",
                "collectibles_found", "secrets_found", "rooms_visited", "quests_completed"}) do
                out[#out + 1] = {label = {key = "records." .. key},
                    value = {key = "records.count", params = {count = stats[key]}}}
            end
            return out
        end}
end

-- Called at gameplay-services bootstrap, before SaveManager applies the save.
-- Like elevator persistence, the provider census explicitly ensures this seam.
function M.ensure_checkpoint_provider()
    local Checkpoint = require "mvtk.core.checkpoint"
    Checkpoint.register_provider("run_stats", {version = 1, order = 210,
        capture = function()
            -- Death-menu Quit may save on shutdown. Until restart succeeds,
            -- retain the last saved statistics rather than the pending carry.
            return normalized(pending and pending.saved or state)
        end,
        apply = function(data) state = normalized(data) end,
        defaults = function() state = normalized(nil) end,
    })
    local Records = require "mvtk.ui.screens.journal_records"
    Records.add_section(M.time_section())
    Records.add_section(M.statistics_section())
    return true
end

function M.after_restart_load(load_ok, fee_ok)
    local carry = pending
    if not carry or not load_ok then pending = nil; return false end
    local Checkpoint = require "mvtk.core.checkpoint"
    if Checkpoint.slot ~= carry.slot or Checkpoint.is_save_sandboxed() then pending = nil; return false end
    state = carry.live
    -- A failed death-fee write keeps the death screen open for Restart retry.
    -- Retain the same carry until that retry succeeds, without adding a death.
    if fee_ok ~= false then pending = nil end
    return true
end
function M.on_session_start()
    -- Continue/new-game begins a new session; a pending death never crosses it.
    pending = nil
    hud_second = M.playtime_s()
    post_timer(hud_second)
end

GameEvents.on("ending_reached", function(event)
    if require("mvtk.core.checkpoint").is_save_sandboxed() then return end
    local id = event.ending_id
    if type(id) ~= "string" or id == "" then return end
    local Profile = require "mvtk.core.profile_store"
    local records = Profile.get("records")
    records.best_times = records.best_times or {}
    records.endings_seen = records.endings_seen or {}
    local seconds, old = M.playtime_s(), records.best_times[id]
    local changed = records.endings_seen[id] ~= true
    records.endings_seen[id] = true
    if not require("mvtk.core.flags").get("assist_slowed") and (type(old) ~= "number" or seconds < old) then
        records.best_times[id] = seconds
        changed = true
    end
    if changed then Profile.put("records", records) end
    Profile.flush(true)
end)

GameEvents.on("player_died", function()
    local Checkpoint = require "mvtk.core.checkpoint"
    if Checkpoint.is_save_sandboxed() then pending = nil; return end
    state.deaths = state.deaths + 1
    local live = {}
    for _, key in ipairs(fields) do live[key] = state[key] end
    local saved = (((Checkpoint.data or {}).modules or {}).run_stats or {}).data
    pending = {slot = Checkpoint.slot, live = live, saved = normalized(saved)}
end)
for event, counter in pairs({enemy_defeated = "enemies_defeated", boss_defeated = "bosses_defeated",
    quest_completed = "quests_completed", secret_found = "secrets_found", room_visited = "rooms_visited"}) do
    local key = counter
    GameEvents.on(event, function() state[key] = state[key] + 1 end)
end
GameEvents.on("collectible_collected", function(event)
    if event.respawns == false then state.collectibles_found = state.collectibles_found + 1 end
end)
return M
