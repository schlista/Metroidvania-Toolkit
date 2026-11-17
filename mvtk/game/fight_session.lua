-- Shared fight-session lifetime. Debug entry points inject their capabilities;
-- trial hosts share this home without depending on debug tools.
-- Practice uses the ordinary last-save restart; trials fail safely in place.
local Checkpoint = require "mvtk.core.checkpoint"
local Game = require "mvtk.game.game_manager"
local Events = require "mvtk.core.game_events"
local Census = require "mvtk.world.census"
local Flags = require "mvtk.core.flags"
local Pause = require "mvtk.core.pause"
local BossDefaults = require "developer.config.boss_defaults"
local M = {}
local session, subscribed, attached, attached_lifetime
local abort_trial

local function clear_trial_filters()
    require("mvtk.abilities.ability_manager").set_use_filter(nil)
    require("mvtk.combat.attack_executor").set_request_filter(nil)
end
local function install_trial_filters(spec)
    local Limits = require "mvtk.game.trial_limits"
    local abilities, attacks = Limits.parse(spec.disabled_abilities), Limits.parse(spec.disabled_attacks)
    require("mvtk.abilities.ability_manager").set_use_filter(function(id) return not abilities[id] end)
    require("mvtk.combat.attack_executor").set_request_filter(function(tag) return not attacks[tag] end)
end

local function cleanup_delay(token)
    local Manager = require "mvtk.bosses.boss_manager"
    local delay
    for _, id in ipairs(Manager.get_active_bosses()) do
        local boss = Manager.get_boss(id)
        if boss and token.identities[require("mvtk.bosses.boss_identity").runtime(boss,id)] then
            delay = math.max(delay or 0, boss.config.defeat_cleanup_delay or BossDefaults.defeat_cleanup_delay)
        end
    end
    return delay or BossDefaults.defeat_cleanup_delay
end

function M.state() return session and session.phase or "idle" end
function M.kind() return session and session.kind end

function M.finish()
    if not session or session.kind ~= "practice" then return false, "No practice is active." end
    if session.phase == "ending" then return false, "Restart already requested." end
    local previous = session.phase
    session.phase = "ending"
    -- Loading/applying gameobjects belongs to main, never the calling GUI.
    local ok, err = pcall(msg.post, "main:/main_go#script", "restart_game", {reason="boss_practice"})
    if not ok then session.phase = previous; return false, tostring(err) end
    return true
end

-- Driven by a persistent host, never a defeated actor's script-owned timer.
function M.update(dt)
    -- SaveManager.init clears sandbox reasons when starting a new game, after
    -- final() has retained them through shutdown. Never resume from this host.
    if session and session.kind == "practice" and not Checkpoint.is_save_suspended_by("boss_practice") then session = nil end
    local token = session
    if not token or token.kind ~= "practice" or token.phase ~= "fighting" or not token.cleanup_remaining then return end
    if Pause.get() or not Game.is_playing() then return end
    if token.cleanup_deferred then M.finish(); return end
    token.cleanup_remaining = math.max(0, token.cleanup_remaining - math.max(0, dt or 0))
    -- Let the manager's timer and main's scene message complete this frame.
    if token.cleanup_remaining == 0 then token.cleanup_deferred = true end
end

local function subscribe()
    if subscribed then return end
    subscribed = true
    Events.on("boss_defeated", function(event)
        local token = session
        if not token or token.kind ~= "practice" or token.phase ~= "fighting" or not token.remaining[event.boss_id] then return end
        token.remaining[event.boss_id] = nil
        if next(token.remaining) then return end
        -- This listener runs in the dying actor's context. Its timers may be
        -- deleted with it, so the persistent host owns the countdown instead.
        token.cleanup_remaining = cleanup_delay(token)
    end)
end

-- GameManager.final clears its callbacks; the persistent host reattaches once
-- on each new overlay lifetime. Event subscriptions remain module-lifetime.
function M.attach()
    local lifetime = Game.lifetime and Game.lifetime() or 0
    if Game.lifetime and attached and attached_lifetime == lifetime then return end
    attached, attached_lifetime = true, lifetime
    Game.register_state_callback(Game.STATE.GAME_OVER, function()
        if session and session.kind == "trial" then abort_trial(false)
        elseif session then session.phase = "ending" end -- normal death-menu Restart owns reload
    end)
    Game.register_state_callback(Game.STATE.PLAYING, function(old_state)
        if session and session.kind == "trial" and old_state == Game.STATE.LOADING then abort_trial(false)
        elseif session and session.kind == "practice" and session.phase == "ending" and old_state == Game.STATE.LOADING then
            Checkpoint.resume_saves("boss_practice")
            session = nil
        end
    end)
end

function M.start(entry, capabilities, all_abilities)
    if session and session.kind == "trial" then return false, "Finish the trial first." end
    if not capabilities or not capabilities.available() then return false, "Cheats are disabled." end
    if not Game.is_playing() then return false, "Practice requires gameplay." end
    if session or Checkpoint.is_save_suspended_by("boss_practice") then return false, "Practice is already active." end
    if Checkpoint.is_save_suspended_by("dev_tools") then return false, "End the test session first." end
    if require("mvtk.bosses.fight_lock").is_locked(require("mvtk.map.streaming.room_manager").get_current_room()) then
        return false, "Leave the locked fight before practising."
    end
    if not entry or entry.kind ~= "boss" or not entry.identity or not entry.room then
        return false, "No boss selected: run Prepare & Check."
    end
    local members, seen = {entry}, {[entry.identity]=true}
    if entry.arena_id and entry.arena_id ~= "" then
        for _, other in ipairs(Census.entries()) do
            if other.kind == "boss" and other.arena_id == entry.arena_id and not seen[other.identity] then
                members[#members+1] = other; seen[other.identity] = true
            end
        end
    end
    subscribe()
    M.attach()
    -- Must precede flag changes, grants and every possible autosave.
    Checkpoint.suspend_saves("boss_practice")
    clear_trial_filters()
    session = {kind="practice", phase="armed", remaining={}, identities=seen}
    for id in pairs(seen) do session.remaining[id] = true end
    for _, member in ipairs(members) do Flags.clear("boss_defeated_" .. member.identity) end
    if all_abilities then
        local ok, result = require("mvtk.game.grants").grant(capabilities.abilities,
            {source="debug", durable=false, notify=true})
        if not ok then return false, result.message or result.code end
    end
    -- One small message per placement stays below Defold's message-size limit.
    for _, member in ipairs(members) do
        msg.post("main:/main_go#script", "boss_practice_arm", {identity=member.identity})
    end
    local ok, err = capabilities.warp(entry.room)
    if not ok then return false, err or "Warp failed; use End practice to restore the save." end
    session.phase = "fighting"
    return true
end

-- Trial services are lazy so debug practice keeps its original dependency contract.
local trial_subscribed, collider_revision, collider_settings
local function trial_rules() return require "mvtk.game.trial_session" end
local function trial_token()
    return session and session.kind == "trial" and session
end
local function listen_trials()
    if trial_subscribed then return end
    trial_subscribed = true
    Events.on("encounter_cleared", function(e)
        local t = trial_token()
        if t and t.phase == "fighting" then trial_rules().on_cleared(t.rules, e.room_id, e.encounter_id) end
    end)
    Events.on("enemy_defeated", function(e)
        local t = trial_token()
        if t and t.phase == "fighting" then trial_rules().on_defeat(t.rules, e.spawn_owner) end
    end)
    Events.on("player_damaged", function(e)
        local t = trial_token()
        if t and (t.phase == "armed" or t.phase == "fighting") then
            trial_rules().on_damage(t.rules, e.amount)
            t.hud_dirty = true
        end
    end)
end
local function sound(id)
    if id and id ~= "" then require("mvtk.audio.audio").sfx(id) end
end
local function post_reset(t, reason)
    if t.controller.url then msg.post(t.controller.url, "encounter_reset", {reason=reason}) end
end
-- Each release is attempted even if a deleted receiver rejects a message.
local function release_trial(t, reset, keep_result)
    local function attempt(fn)
        local ok, err = pcall(fn)
        if not ok then print("[TRIAL] Cleanup: " .. tostring(err)) end
    end
    attempt(function() require("mvtk.abilities.ability_manager").set_use_filter(nil) end)
    attempt(function() require("mvtk.combat.attack_executor").set_request_filter(nil) end)
    if reset then attempt(function() post_reset(t, reset) end) end
    attempt(function() require("mvtk.bosses.fight_lock").unseal(t.spec.room_id, t.owner) end)
    attempt(function()
        if require("mvtk.map.streaming.room_manager").get_room_bounds(t.spec.room_id) then
            msg.post("main:/room_manager#script", "unlock_room", {room_id=t.spec.room_id, source=t.owner})
        end
    end)
    attempt(function() require("mvtk.player.player_death").unregister_guard("fight_session") end)
    if not keep_result then attempt(function() require("mvtk.ui.hud_bus").post("trial", {state="idle"}) end) end
    if session == t then session = nil end
end
abort_trial = function(publish)
    local t = trial_token()
    if not t then return end
    release_trial(t, "trial_abort")
    if publish and Game.is_playing() then
        Events.emit("trial_failed", {trial_id=t.spec.trial_id, room_id=t.spec.room_id, reason="left"})
    end
end
-- GameManager.final runs even when no debug overlay exists.
function M.reset_lifetime() abort_trial(false) end
function M.owns_encounter(room, encounter)
    local t = trial_token()
    return t and t.spec.room_id == room and t.spec.encounter_id == encounter or false
end
local function heal(t)
    local hp = require("mvtk.player.health_state").get() or 0
    if t.start_health > hp then msg.post(t.player, "heal", {amount=t.start_health-hp}) end
end
local function result_text(t, rank, metric)
    if require("mvtk.player.assist").was_slowed(t.assist_marker) then return {key="trial.no_best_slowed"} end
    local rank_name = t.settings.ranks[rank] and {text=t.settings.ranks[rank].name} or ""
    if t.rules.goal == "survive" then
        return {key="trial.result_hits", params={rank=rank_name,
            hits={forms={one="trial.hits_one",other="trial.hits_other"}, count=metric, params={count=metric}}}}
    end
    return {key=rank > 0 and "trial.result" or "trial.result_unranked", params={rank=rank_name,
        time=require("mvtk.ui.time_text").playtime(math.floor(metric / 10), metric % 10)}}
end
local function succeed(t)
    local Rules = trial_rules()
    local metric = Rules.metric(t.rules)
    local rank = Rules.rank(t.spec, metric)
    local id = t.spec.trial_id
    local clear_flag = t.spec.clear_flag
    if not clear_flag or clear_flag == "" then clear_flag = "trial_cleared_" .. id end
    local first = not Flags.has(clear_flag)
    local best = Rules.better(Flags.get("trial_rank_" .. id), Flags.get("trial_best_" .. id), rank, metric)
    best = best and not require("mvtk.player.assist").was_slowed(t.assist_marker)
    local applied = false
    local function apply()
        local mark = Events.hold()
        local ok, err = pcall(function()
            -- A blank reward (the template default) grants nothing; grant text never parses "".
            local reward = t.spec.trial_reward
            if first and type(reward) == "string" and reward:find("%S")
                and not Flags.has("grant_once:trial:" .. id) then
                local granted, why = require("mvtk.game.grants").grant(reward, {
                    source="trial", reason="trial_completed", once_key="trial:" .. id, notify=true, durable=false})
                assert(granted, why and why.message or "Trial reward failed")
            end
            Flags.set(clear_flag, true)
            if best then
                Flags.set("trial_rank_" .. id, rank)
                Flags.set("trial_best_" .. id, metric)
            end
            Events.emit("trial_completed", {trial_id=id, room_id=t.spec.room_id, goal=t.rules.goal,
                rank=rank, metric=metric, first_clear=first, new_best=best})
        end)
        if not ok then Events.discard(mark); error(err, 0) end
        Events.release(mark)
        applied = true
    end
    if t.settings.autosave_on_clear then
        local ok, err = Checkpoint.batch("trial_completed", apply)
        if not ok and applied and not tostring(err):match("^save_suspended:") then
            print("[TRIAL] Clear save failed: " .. tostring(err))
        elseif not applied then error(err or "Trial result failed", 0) end
    else apply() end
    if t.settings.restore_health then heal(t) end
    if t.rules.goal ~= "clear" then post_reset(t, "trial_complete") end
    require("mvtk.ui.notices").post({kind="trial", key="trial_" .. id,
        title={key="trial.complete"}, text=result_text(t, rank, metric)})
    sound(t.settings.success_sfx)
end
local function fail(t, reason)
    Events.emit("trial_failed", {trial_id=t.spec.trial_id, room_id=t.spec.room_id, reason=reason})
    -- The arrival service owns cancellation, fading and actual position delivery.
    msg.post(t.player, require("mvtk.core.constants").MSG.SET_POSITION, {
        position=t.host.position, position_kind="feet", room_id=t.spec.room_id, arrival_fade_out=t.settings.return_fade_out,
        arrival_fade_in=t.settings.return_fade_in, reset_motion=true, reason="trial"})
    post_reset(t, "trial_failed")
    heal(t)
    msg.post("main:/toast_gui#toast", "toast", {key="trial.failed." .. reason, duration=t.settings.result_duration})
    sound(t.settings.fail_sfx)
end
local function publish_trial(t, state, result)
    require("mvtk.ui.hud_bus").post("trial", {state=state,trial_goal=t.rules.goal,
        defeat_target=t.spec.defeat_target,time_limit=t.spec.time_limit,no_damage=t.spec.no_damage,
        disabled_abilities=t.spec.disabled_abilities,disabled_attacks=t.spec.disabled_attacks,
        seconds=t.countdown,tenths=t.rules.elapsed,hits=t.rules.hits,
        duration=t.settings.result_duration,
        title=result and {key=result.result == "success" and "trial.complete" or "trial.failed." .. result.reason},
        text=result and (result.result == "success"
            and result_text(t,trial_rules().rank(t.spec,trial_rules().metric(t.rules)),trial_rules().metric(t.rules))
            or {key="trial.failed." .. result.reason})})
    t.hud_dirty = false
end
function M.start_trial(spec, host)
    if session or Checkpoint.is_save_suspended_by("boss_practice") then return false, "trial.busy" end
    -- A running countdown (WM09) refuses trials; read without a require cycle.
    local countdown = package.loaded["mvtk.game.countdown"]
    if countdown and countdown.running and countdown.running() then return false, "countdown.busy" end
    clear_trial_filters()
    if not Game.is_playing() then return false, "trial.unavailable" end
    if not spec or not host or not host.position or not spec.trial_id or spec.trial_id == "" then
        return false, "trial.unavailable"
    end
    local room = spec.room_id
    local Lock = require "mvtk.bosses.fight_lock"
    if Lock.is_locked(room) then return false, "trial.locked" end
    if spec.requires_flag and spec.requires_flag ~= "" and not Flags.has(spec.requires_flag) then
        return false, "trial.locked"
    end
    local controller = require("mvtk.enemies.encounter_registry").controller(room, spec.encounter_id)
    if not controller or controller.encounter_start ~= "on_signal" or not controller.repeatable
        or not controller.runtime or (controller.runtime.state ~= "idle" and controller.runtime.state ~= "cleared")
        or not controller.url or not controller.owner then return false, "trial.unavailable" end
    if controller.requires_flag and controller.requires_flag ~= "" and not Flags.has(controller.requires_flag) then
        return false, "trial.locked"
    end
    local Settings = require "developer.config.runtime_settings"
    if collider_revision ~= Settings.revision() then
        collider_settings, collider_revision = Settings.get_player_settings(), Settings.revision()
    end
    local Rooms = require "mvtk.map.streaming.room_manager"
    local player = require("mvtk.prefabs.prefab_utils").get_player_url()
    if Rooms.get_current_room() ~= room then return false, "trial.unavailable" end
    if not player or not go.exists(player) then return false, "trial.unavailable" end
    go.update_world_transform(player)
    local tiles = require "developer.config.tile_settings"
    if not require("mvtk.game.boss_setup").room_entry_clear(go.get_world_position(player), Rooms.get_room_bounds(room),
        collider_settings.collider_half_width, collider_settings.collider_half_height,
        tiles.width, tiles.height, Rooms.get_room_doors(room)) then return false, "trial.doorway" end
    local settings = Settings.section("trial_settings", require "developer.config.trial_settings")
    local copy = {}; for k,v in pairs(spec) do copy[k] = v end
    copy.encounter_owner = controller.owner
    local t = {kind="trial", phase="armed", host=host, spec=copy, controller=controller,
        assist_marker=require("mvtk.player.assist").run_marker(),
        owner="trial:" .. room .. ":" .. copy.trial_id, start_health=require("mvtk.player.health_state").get() or 1,
        countdown=math.max(0, settings.countdown), settings=settings, player=player, rules=trial_rules().new(copy)}
    session = t
    local ok, err = pcall(function()
        M.attach(); listen_trials()
        Lock.seal(room, t.owner)
        msg.post("main:/room_manager#script", "lock_room", {room_id=room, source=t.owner})
        require("mvtk.player.player_death").register_guard("fight_session", function(self)
            if session ~= t or (t.phase ~= "armed" and t.phase ~= "fighting") then return false end
            self.health = 1
            require("mvtk.player.resources").clamp_health(self)
            msg.post("main:/mode_hud#mode_hud", "hud_health", {hp=self.health, hp_max=self.max_health})
            trial_rules().on_death(t.rules)
            return true
        end)
        Events.emit("trial_started", {trial_id=copy.trial_id, room_id=room, goal=t.rules.goal})
        publish_trial(t, "countdown")
        sound(settings.start_sfx)
    end)
    if not ok then release_trial(t, "trial_abort"); print("[TRIAL] Start failed: " .. tostring(err)); return false, "trial.unavailable" end
    return true
end
function M.host_update(host, dt)
    local t = trial_token()
    if not t or t.host ~= host then return end
    if require("mvtk.map.streaming.room_manager").get_current_room() ~= t.spec.room_id then abort_trial(true); return end
    if Pause.get() or not Game.is_playing() then return end
    local ok, err = pcall(function()
        dt = math.max(0, dt or 0) * Pause.dt_scale()
        if not trial_rules().outcome(t.rules) then
            if t.phase == "armed" then
                t.countdown = math.max(0, t.countdown - dt)
                if t.countdown == 0 then
                    install_trial_filters(t.spec)
                    t.phase = "fighting"
                    msg.post(t.controller.url, "activate", {})
                    publish_trial(t, "fighting")
                end
            elseif t.phase == "fighting" then trial_rules().tick(t.rules, dt) end
        end
        local result = trial_rules().outcome(t.rules)
        if result then
            t.phase = "resolving"
            if result.result == "success" then succeed(t) else fail(t, result.reason) end
            publish_trial(t, "result", result)
            release_trial(t, nil, true)
        elseif t.hud_dirty then
            publish_trial(t, t.phase == "armed" and "countdown" or "fighting")
        end
    end)
    if not ok then release_trial(t, "trial_abort"); print("[TRIAL] Session failed: " .. tostring(err)) end
end
function M.host_final(host)
    local t = trial_token()
    if t and t.host == host then abort_trial(true) end
end
return M
