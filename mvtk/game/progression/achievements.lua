-- Profile-wide goals. Only the pure event hub is loaded at bootstrap; no provider.
local GameEvents = require "mvtk.core.game_events"
local M = {}
local state, busy, pending = nil, false, {}
local config, config_revision
local session_prepared = false
local function whole(n)
    return type(n)=="number" and n==n and n<math.huge and math.max(0,math.floor(n)) or 0
end
local function normalized(data)
    local out={unlocked={},counters={}}
    for _,kind in ipairs({"unlocked","counters"}) do
        local source=type(data)=="table" and data[kind]
        for id,n in pairs(type(source)=="table" and source or {}) do
            if type(id)=="string" and id~="" and type(n)=="number" and n==n and n>=0 and n<math.huge then out[kind][id]=whole(n) end
        end
    end
    return out
end
-- Every hub event reaches this module, even while it is off: read once per settings revision.
function M.settings()
    local Runtime=require "developer.config.runtime_settings"
    local revision=Runtime.revision()
    if config==nil or config_revision~=revision then
        config,config_revision=Runtime.section("achievements",require "developer.config.achievements"),revision
    end
    return config
end
local function load()
    if not state then state=normalized(require("mvtk.core.profile_store").get("achievements")) end
end
function M.snapshot() load(); return normalized(state) end
function M.is_unlocked(id) load(); return state.unlocked[id]~=nil end
local function put(force)
    local Profile=require "mvtk.core.profile_store"
    Profile.put("achievements",normalized(state))
    return Profile.flush(force)
end
local function matches(t, name, event)
    if t.type~="event" or t.event~=name then return false end
    if name=="gate_opened" and event.temporary==true and (t.where or {}).temporary~=true then return false end
    for key,value in pairs(t.where or {}) do if event[key]~=value then return false end end
    return true
end
local function reached(id,t)
    if t.type=="event" then return (state.counters[id] or 0)>=t.count end
    if t.type=="flag" then return require("mvtk.core.flags").has(t.flag) end
    if t.type=="item" then return require("mvtk.core.inventory").count(t.item)>=t.count end
    if t.type=="currency" then return require("mvtk.core.inventory").get_currency()>=t.amount end
    if t.type=="level" then return require("mvtk.game.progression.progression_manager").get_level()>=t.level end
    if t.type=="completion" then
        local percent=require("mvtk.game.completion_tracker").percent()
        if t.category then
            percent=nil
            local Tracker=require "mvtk.game.completion_tracker"
            for _,row in ipairs(Tracker.breakdown()) do
                if row.id==t.category and row.total>0 then
                    percent=math.floor(100*row.found/row.total+(Tracker.settings().rounding=="round" and 0.5 or 0))
                end
            end
        end
        return percent~=nil and percent>=t.percent
    end
    if t.type=="ending" then
        return require("mvtk.game.completion").data().id==t.ending_id
            and (t.max_playtime_s==nil or (not require("mvtk.core.flags").has("assist_slowed")
                and require("mvtk.game.run_stats").playtime_s()<=t.max_playtime_s))
    end
    if t.type=="quests_completed" then return require("mvtk.game.run_stats").snapshot().quests_completed>=t.count end
    if t.type=="all_of" then
        for _,ref in ipairs(t.ids) do if state.unlocked[ref]==nil then return false end end
        return #t.ids>0
    end
    return false
end
local function unlock(id,row,cfg)
    -- Persist before publishing any fact, feedback, reward or platform call.
    state.unlocked[id]=os.time()
    local ok=put(true)
    if not ok then
        state.unlocked[id]=nil
        require("mvtk.core.profile_store").put("achievements",normalized(state))
        return false
    end
    GameEvents.emit("achievement_unlocked",{achievement_id=id,category=row.category or ""})
    if cfg.notify then
        require("mvtk.ui.notices").post({kind="achievement",title={key="notice.achievement_unlocked"},
            text=row.name, sound=cfg.sfx, key="achievement_"..id})
    elseif cfg.sfx and cfg.sfx~="" then require("mvtk.audio.audio").sfx(cfg.sfx) end
    if row.reward then require("mvtk.game.grants").grant(row.reward,{source="reward",
        reason="achievement_unlocked",once_key="achievement:"..id}) end
    require("mvtk.platform.platform_services").unlock_achievement(id)
    return true
end
local function evaluate(name,event,cfg)
    load()
    local ids={}; for id in pairs(cfg.achievements or {}) do ids[#ids+1]=id end; table.sort(ids)
    local changed=false
    for _,id in ipairs(ids) do
        local t=cfg.achievements[id].trigger
        if state.unlocked[id]==nil and matches(t,name,event) then
            state.counters[id]=math.min(t.count,(state.counters[id] or 0)+1); changed=true
        end
    end
    -- Keep counters in memory while blocked; publish no profile write or unlock effects.
    if require("mvtk.player.assist").blocks_achievements() and require("mvtk.core.flags").has("assist_used") then return end
    -- Iterate all_of dependencies without relying on hash order or event depth.
    local again=true
    while again do
        again=false
        for _,id in ipairs(ids) do
            local row=cfg.achievements[id]
            if state.unlocked[id]==nil and reached(id,row.trigger) and unlock(id,row,cfg) then again=true; changed=false end
        end
    end
    if changed then put(false) end
end
local function receive(name,event)
    if require("mvtk.core.checkpoint").is_save_sandboxed() then return end
    local cfg=M.settings()
    if cfg.enabled~=true then return end
    -- Reward and achievement events can re-enter from the synchronous hub.
    -- Drain them after the current unlock's ordered effects have completed.
    pending[#pending+1]={name=name,event=event or {},cfg=cfg}
    if busy then return end
    busy=true
    local ok,err=pcall(function()
        while #pending>0 do
            local next_event=table.remove(pending,1)
            if not require("mvtk.core.checkpoint").is_save_sandboxed() then
                evaluate(next_event.name,next_event.event,next_event.cfg)
            end
        end
    end)
    busy=false; pending={}
    if not ok then error(err) end
end
-- Discard the previous slot's in-memory blocked counters before startup facts.
-- GameplayServices holds assist events until every quiet reset is complete.
function M.before_session_start()
    state, session_prepared = nil, false
    if require("mvtk.core.checkpoint").is_save_sandboxed() or M.settings().enabled~=true then return end
    load()
    session_prepared = true
end
function M.on_session_start()
    if require("mvtk.core.checkpoint").is_save_sandboxed() then return end
    if M.settings().enabled~=true then return end
    -- Direct callers may not run the quiet preparation pass.
    if not session_prepared then state=normalized(require("mvtk.core.profile_store").get("achievements")) end
    session_prepared = false
    local ids={}; for id in pairs(state.unlocked) do ids[#ids+1]=id end; table.sort(ids)
    require("mvtk.platform.platform_services").sync_achievements(ids)
    receive(nil,{})
end
for name in pairs(GameEvents.EVENTS) do
    local event_name=name
    GameEvents.on(event_name,function(event) receive(event_name,event) end)
end
return M
