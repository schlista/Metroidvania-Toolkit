-- Countdown events (WM09): one countdown at a time that runs across rooms,
-- holds in menus, dialogue and cutscenes, and never survives a load.
-- Safe for GameManager's headless loaders: only GameEvents is required at
-- load; everything else is a call-time require. GameManager.update ticks it.
--
-- Definitions live in developer/config/countdowns.lua. A countdown starts from
-- its start_when condition (re-evaluated only when Presence.revision moves) or
-- from M.start (Countdown Zones). While it runs, countdown_<id>_active is set.
local GameEvents = require "mvtk.core.game_events"
-- Not literal requires: GameManager requires this module, and Bob refuses
-- require cycles. FightSession is read through package.loaded for the same reason.
local GAME_MODULE = "mvtk.game.game_manager"
local FIGHT_MODULE = "mvtk.game.fight_session"
local M = {}
M.SUSPENSION = "countdown"
M.MUSIC_OWNER = "countdown"

local run
local settings_cache, settings_revision
local checked_revision
local started_while_true = {}
local attached, attached_lifetime

local function rules() return require "mvtk.game.countdown_rules" end
local function clock() return require "mvtk.game.trial_session" end

-- Settings are read through Game Settings overrides once per revision.
function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if settings_revision ~= revision or not settings_cache then
        settings_cache = Runtime.section("countdowns", require "developer.config.countdowns")
        settings_revision = revision
        checked_revision = nil
    end
    return settings_cache
end
function M.spec(id) return rules().entry(M.settings(), id) end

function M.running() return run and run.id or nil end
function M.blocks_travel() return run ~= nil and run.spec.block_travel == true end
function M.blocks_saves() return run ~= nil and run.spec.block_saves == true end

-- Display state for the HUD block: integer tenths left.
function M.current()
    if not run then return nil end
    local remaining = math.max(0, run.rules.limit - run.rules.elapsed)
    local warning = false
    for _, seconds in ipairs(run.spec.warnings) do
        -- A warning time at or above the duration never applies.
        local at = math.floor(seconds * 10 + 0.0000001)
        if at < run.rules.limit and remaining <= at then warning = true end
    end
    return {countdown_id = run.id, label = run.spec.label, remaining = remaining,
        elapsed = run.rules.elapsed, warning = warning}
end

-- HUD block (mvtk/ui/hud_blocks/countdown.lua). Posts only when the shown
-- value changes: whole seconds, or tenths below tenths_below. The block formats.
local function hud(data)
    local ok, err = pcall(function() require("mvtk.ui.hud_bus").post("countdown", data) end)
    if not ok then print("[COUNTDOWN] HUD failed: " .. tostring(err)) end
end
local function display(state)
    local shown = M.current()
    if not shown or run ~= state then return end
    local below = tonumber(M.settings().tenths_below) or 0
    local tenths = shown.remaining < math.floor(below * 10 + 0.0000001)
    local value = tenths and shown.remaining or math.floor((shown.remaining + 9) / 10)
    local key = (tenths and "t" or "s") .. value .. (shown.warning and "w" or "")
    if state.shown == key then return end
    state.shown = key
    hud({state = "running", label = shown.label, remaining = shown.remaining,
        tenths_shown = tenths, warning = shown.warning})
end
local function result(state, data)
    data.state, data.label = "result", state.spec.label
    data.duration = tonumber(M.settings().result_duration) or 0
    hud(data)
end

local function sound(id)
    if type(id) == "string" and id ~= "" then
        local ok, err = pcall(function() require("mvtk.audio.audio").sfx(id) end)
        if not ok then print("[COUNTDOWN] Sound failed: " .. tostring(err)) end
    end
end
local function attempt(label, fn)
    local ok, err = pcall(fn)
    if not ok then print("[COUNTDOWN] " .. label .. ": " .. tostring(err)) end
end
local function player_url() return require("mvtk.prefabs.prefab_utils").get_player_url() end

-- Room-local start point: zones pass theirs; otherwise the player's position.
local function room_origin(room_id)
    local Rooms = require "mvtk.map.streaming.room_manager"
    return require("mvtk.map.streaming.room_geometry").compute_spawn_xy(Rooms.get_room_data(room_id))
end
local function player_start()
    local found
    attempt("Start point", function()
        local url = player_url()
        local room = require("mvtk.map.streaming.room_manager").get_current_room()
        if not url or not room or not go.exists(url) then return end
        local pos = go.get_world_position(url)
        local ox, oy = room_origin(room)
        found = {room_id = room, local_x = pos.x - ox, local_y = pos.y - oy}
    end)
    return found
end

local function new_clock(spec) return clock().new({time_limit = spec.duration}) end
local function mark_passed_warnings(state)
    state.warned = {}
    local remaining = state.rules.limit - state.rules.elapsed
    for i, seconds in ipairs(state.spec.warnings) do
        if math.floor(seconds * 10 + 0.0000001) >= remaining then state.warned[i] = true end
    end
end

-- Ends the run's world effects. keep_suspension retains the save suspension
-- through GameManager.final: its on_exit completes at the next session start.
local function teardown(state, keep_suspension, keep_display)
    if run ~= state then return end
    run = nil
    if not keep_display then hud({state = "idle"}) end
    attempt("Flag", function()
        local Flags = require "mvtk.core.flags"
        Flags.clear(rules().active_flag(state.id))
    end)
    if not keep_suspension then
        attempt("Saves", function() require("mvtk.core.checkpoint").resume_saves(M.SUSPENSION) end)
    end
    if state.music then attempt("Music", function() require("mvtk.bosses.boss_music").pop(M.MUSIC_OWNER) end) end
    if state.tint then
        attempt("Tint", function() msg.post("main:/screen_effect_overlay#gui", "clear_effect", {}) end)
    end
end
local function failed(id, reason)
    GameEvents.emit("countdown_failed", {countdown_id = id, reason = reason})
end

local function on_exit()
    require("mvtk.core.checkpoint").resume_saves(M.SUSPENSION)
    return true
end

-- GameManager.final clears state callbacks; reattach once per lifetime.
function M.attach()
    -- main.script loads GameManager before any session; headless hosts may not.
    local Game = package.loaded[GAME_MODULE]
    if type(Game) ~= "table" or not Game.register_state_callback then return end
    local lifetime = Game.lifetime and Game.lifetime() or 0
    if attached and attached_lifetime == lifetime then return end
    attached, attached_lifetime = true, lifetime
    Game.register_state_callback(Game.STATE.GAME_OVER, function()
        local state = run
        if state then teardown(state); failed(state.id, "death") end
    end)
    Game.register_state_callback(Game.STATE.PLAYING, function(old_state)
        if old_state ~= Game.STATE.LOADING then return end
        -- A countdown never survives a load, including one saved without block_saves.
        local state = run
        if state then teardown(state); failed(state.id, "left") end
        M.clear_active_flags()
    end)
end

function M.clear_active_flags()
    local Flags = require "mvtk.core.flags"
    for _, id in ipairs(rules().ids(M.settings())) do
        if Flags.has(rules().active_flag(id)) then Flags.clear(rules().active_flag(id)) end
    end
    started_while_true, checked_revision = {}, nil
end

-- Returns true, or false and a reason: unknown, invalid, busy, fight,
-- finished or unavailable.
function M.start(id, opts)
    opts = opts or {}
    local spec = M.spec(id)
    if not spec then return false, "unknown" end
    if spec.duration <= 0 then return false, "invalid" end
    if run then return false, "busy" end
    local Game = package.loaded[GAME_MODULE]
    if type(Game) == "table" and Game.is_playing and not Game.is_playing() then return false, "unavailable" end
    local fights = package.loaded[FIGHT_MODULE]
    if type(fights) == "table" and fights.state and fights.state() ~= "idle" then return false, "fight" end
    local Flags = require "mvtk.core.flags"
    if not spec.repeatable and Flags.has(spec.finish_flag) then return false, "finished" end
    local start = opts.room_id and {room_id = opts.room_id, local_x = tonumber(opts.local_x) or 0,
        local_y = tonumber(opts.local_y) or 0, position_kind = opts.position_kind} or player_start()
    local state = {id = id, spec = spec, rules = new_clock(spec), start = start,
        assist_marker = require("mvtk.player.assist").run_marker(),
        source = type(opts.source) == "string" and opts.source or "script"}
    mark_passed_warnings(state)
    run = state
    M.attach()
    Flags.set("countdown_" .. id .. "_active", true)
    -- Must precede any autosave the run could otherwise reach.
    if spec.block_saves then require("mvtk.core.checkpoint").suspend_saves(M.SUSPENSION, on_exit) end
    if spec.music ~= "" then
        attempt("Music", function()
            local Music = require "mvtk.bosses.boss_music"
            state.music = Music.push(M.MUSIC_OWNER, {music_theme = spec.music}, Music.PRIORITY.countdown) ~= false
        end)
    end
    if spec.tint then
        state.tint = true
        local t = spec.tint
        attempt("Tint", function()
            msg.post("main:/screen_effect_overlay#gui", "set_effect",
                {color = vmath.vector4(t.r or 0, t.g or 0, t.b or 0, t.a or 1), alpha = t.a or 1})
        end)
    end
    display(state)
    GameEvents.emit("countdown_started", {countdown_id = id, source = state.source})
    return true
end

function M.cancel(id)
    local state = run
    if not state or (id and state.id ~= id) then return false end
    teardown(state, false, true)
    result(state, {text = {key = "countdown.cancelled"}})
    failed(state.id, "cancelled")
    return true
end

-- Finish the running countdown. Mirrors the trial result: resume saves first,
-- then one batch with the reward, finish flag, best time and event.
function M.finish(id)
    local state = run
    if not state or (id and state.id ~= id) then return false end
    local spec, settings = state.spec, M.settings()
    local tenths = state.rules.elapsed
    local Flags = require "mvtk.core.flags"
    local first = not Flags.has(spec.finish_flag)
    local best = spec.best_time and clock().better(0, Flags.get(rules().best_flag(state.id)), 0, tenths) or false
    local slowed = require("mvtk.player.assist").was_slowed(state.assist_marker)
    best = best and not slowed
    teardown(state, false, true)
    result(state, {title = {key = "countdown.complete"}, tenths = tenths, new_best = best,
        text = slowed and {key = "countdown.no_best_slowed"} or nil})
    local applied = false
    local function apply()
        local mark = GameEvents.hold()
        local ok, err = pcall(function()
            local reward, once = spec.reward, "countdown:" .. state.id
            if first and reward:find("%S") and not Flags.has("grant_once:" .. once) then
                local granted, why = require("mvtk.game.grants").grant(reward, {source = "countdown",
                    reason = "countdown_finished", once_key = once, notify = true, durable = false})
                assert(granted, why and why.message or "Countdown reward failed")
            end
            local finish_flag = spec.finish_flag
            Flags.set(finish_flag, true)
            if best then Flags.set("countdown_best_" .. state.id, tenths) end
            GameEvents.emit("countdown_finished", {countdown_id = state.id, tenths = tenths,
                new_best = best, first_clear = first})
        end)
        if not ok then GameEvents.discard(mark); error(err, 0) end
        GameEvents.release(mark)
        applied = true
    end
    if settings.autosave_on_finish then
        local ok, err = require("mvtk.core.checkpoint").batch("countdown_finished", apply)
        if not ok and applied and not tostring(err):match("^save_suspended:") then
            print("[COUNTDOWN] Finish save failed: " .. tostring(err))
        elseif not applied then
            print("[COUNTDOWN] Finish failed: " .. tostring(err)); return false
        end
    else
        local ok, err = pcall(apply)
        if not ok then print("[COUNTDOWN] Finish failed: " .. tostring(err)); return false end
    end
    sound(settings.finish_sfx)
    return true, {tenths = tenths, new_best = best, first_clear = first}
end

local function timeout(state)
    local spec, settings = state.spec, M.settings()
    sound(settings.fail_sfx)
    if spec.on_timeout == "restart" then
        failed(state.id, "time")
        local start = state.start
        if start then
            attempt("Restart", function()
                local x, y = room_origin(start.room_id)
                msg.post(player_url(), require("mvtk.core.constants").MSG.SET_POSITION, {
                    position = vmath.vector3(x + start.local_x, y + start.local_y, 0), room_id = start.room_id,
                    position_kind = start.position_kind,
                    arrival_fade_out = settings.return_fade_out, arrival_fade_in = settings.return_fade_in,
                    reset_motion = true, reason = "countdown"})
            end)
        end
        state.rules = new_clock(spec)
        state.assist_marker = require("mvtk.player.assist").run_marker()
        mark_passed_warnings(state)
        state.shown = nil
        display(state)
        GameEvents.emit("countdown_started", {countdown_id = state.id, source = "restart"})
        return
    end
    teardown(state, false, true)
    result(state, {text = {key = "countdown.failed.time"}})
    failed(state.id, "time")
    attempt("Timeout", function()
        local url = player_url()
        if spec.on_timeout == "return_safe" then
            -- Returns that are switched off mean a kill, as hazard zones decide.
            local Contact = require "mvtk.hazards.hazard_contact"
            if Contact.effective("safe_return", true, Contact.settings()) == "safe_return" then
                msg.post(url, "mvtk_hazard_contact", {mode = "safe_return", lethal = true, return_damage = 0})
                return
            end
        end
        msg.post(url, "mvtk_death", {reason = "countdown"})
    end)
end

-- start_when is evaluated only when Presence.revision moves. A countdown
-- starts when its condition holds and it has not already started while the
-- condition stayed true; a load or session start forgets that memory.
local function check_conditions()
    local settings = M.settings()
    local ids, any = rules().ids(settings), false
    for _, id in ipairs(ids) do
        local row = settings.countdowns[id]
        if type(row.start_when) == "string" and row.start_when:match("%S") then any = true; break end
    end
    if not any then return end
    local Presence = require "mvtk.world.presence"
    local revision = Presence.revision()
    if checked_revision == revision then return end
    checked_revision = revision
    for _, id in ipairs(ids) do
        local spec = rules().entry(settings, id)
        if spec.start_when ~= "" then
            local holds = Presence.holds(spec.start_when)
            if holds ~= true then started_while_true[id] = nil
            elseif not started_while_true[id] and not run then
                if M.start(id, {source = "condition"}) then started_while_true[id] = true end
            end
        end
    end
end

-- counting: PLAYING and not paused. Dialogue and cutscenes block input, which
-- holds the clock too (the feature HUD's frozen rule).
function M.tick(dt, counting)
    if not counting then return end
    check_conditions()
    local state = run
    if not state then return end
    if require("mvtk.rooms.input_controller").get_blocked() then return end
    dt = tonumber(dt) or 0
    if dt ~= dt or dt <= 0 or dt == math.huge then return end
    dt = dt * require("mvtk.core.pause").dt_scale()
    clock().tick(state.rules, dt)
    local remaining = state.rules.limit - state.rules.elapsed
    for i, seconds in ipairs(state.spec.warnings) do
        if not state.warned[i] and remaining <= math.floor(seconds * 10 + 0.0000001) then
            state.warned[i] = true
            sound(M.settings().warning_sfx)
        end
    end
    if clock().outcome(state.rules) and run == state then timeout(state) else display(state) end
end

-- Gameplay services: a new session never inherits a run or an active flag.
function M.before_session_start()
    local state = run
    if state then teardown(state) end
    M.clear_active_flags()
end
function M.on_session_start() M.attach() end

-- GameManager.final: Quit to title. No events; the save suspension stays so
-- the game_exit save and the next SaveManager.init complete it through on_exit.
function M.reset_lifetime()
    local state = run
    if state then teardown(state, true) end
    started_while_true, checked_revision = {}, nil
end

return M
