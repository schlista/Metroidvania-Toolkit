-- Save-slot quest owner. Hub callbacks and future GUI actions use Lua services only.
local Events = require "mvtk.core.game_events"
local State = require "mvtk.game.quests.quest_state"
local M = {}
local state,config,config_revision={},nil,nil
local busy,pending=false,{}
local serial=0
function M.revision() return serial end
function M.settings()
    local Runtime=require "developer.config.runtime_settings"
    local revision=Runtime.revision()
    if config==nil or config_revision~=revision then
        config,config_revision=Runtime.section("quests",require "developer.config.quests"),revision
    end
    return config
end
local function enabled() return M.settings().enabled==true end
local function row(id) return (M.settings().quests or {})[id] end
local function entry(id) if not state[id] then state[id]=State.normalize(nil) end; return state[id] end
function M.get(id) return State.normalize(state[id]) end
function M.get_state(id) return M.get(id).state end
function M.is_complete(id) local s=M.get_state(id); return s=="completed" or s=="turned_in" end
function M.snapshot()
    local out={quests={}}
    for id,s in pairs(state) do out.quests[id]=State.normalize(s) end
    return out
end
local function apply(data)
    state={}; serial=serial+1
    for id,s in pairs(type(data)=="table" and type(data.quests)=="table" and data.quests or {}) do
        if type(id)=="string" and type(s)=="table" and row(id) then state[id]=State.normalize(s) end
    end
end
-- Apply/defaults intentionally perform no evaluation, mirror writes, events or grants.
do
local Checkpoint=require "mvtk.core.checkpoint"
Checkpoint.register_provider("quests",{version=2,order=48,
    migrations={ [1]=function() return {} end },
    capture=M.snapshot, apply=apply, defaults=function() state={}; serial=serial+1 end})
end
-- Post at the transition, before held mirror/event facts can evaluate another step.
-- Queue listeners could otherwise publish a stale started notice after completion.
local function notice(id,key)
    local cfg=M.settings()
    if cfg.enabled==true and cfg.notify==true then
        require("mvtk.ui.notices").post({kind="quest",key="quest_"..id,
            title={key=key},text=row(id).title})
    end
end
local function started(id)
    serial=serial+1
    local Flags=require "mvtk.core.flags"
    Flags.set("quest_started_"..id,true)
    notice(id,"notice.quest_started")
    Events.emit("quest_started",{quest_id=id})
end
local function completed(id)
    serial=serial+1
    local Flags=require "mvtk.core.flags"
    Flags.set("quest_completed_"..id,true)
    notice(id,"notice.quest_completed")
    Events.emit("quest_completed",{quest_id=id})
end
local function advanced(id,step)
    serial=serial+1
    local Flags=require "mvtk.core.flags"
    if step.set_flag and step.set_flag~="" then Flags.set(step.set_flag,true) end
    local s=entry(id)
    State.complete_turn_in(s,row(id).steps[s.step],Flags.has)
    notice(id,"notice.quest_updated")
    Events.emit("quest_step",{quest_id=id,step_id=step.id,step=s.step})
    if s.state=="completed" then completed(id) end
end
local receive
-- Hold facts until transitions and mirrors agree, then drain reentrant objectives.
local function change(callback)
    local mark=Events.hold()
    local ok,result=pcall(callback)
    if ok then Events.release(mark) else Events.discard(mark); error(result,0) end
    if result then receive(nil,{}) end
    return result
end
function M.start(id)
    if not enabled() or not row(id) then return false end
    return change(function()
        local s=entry(id)
        if not State.start(s) then return false end
        started(id)
        if State.complete_turn_in(s,row(id).steps[1],require("mvtk.core.flags").has) then completed(id) end
        return true
    end)
end
function M.advance(id,step_id)
    if not enabled() or not row(id) then return false end
    return change(function()
        local s=entry(id)
        local step=row(id).steps[s.step]
        if step and step.requires_flag and step.requires_flag~="" and not require("mvtk.core.flags").has(step.requires_flag) then return false end
        local ok,done=State.advance(s,row(id).steps,step_id)
        if ok then advanced(id,done) end
        return ok
    end)
end
function M.complete(id)
    if not enabled() or not row(id) then return false end
    return change(function() if not State.complete(entry(id)) then return false end; completed(id); return true end)
end
function M.fail(id)
    if not enabled() or not row(id) then return false end
    return change(function()
        if not State.fail(entry(id)) then return false end
        serial=serial+1
        local Flags=require "mvtk.core.flags"
        Flags.set("quest_failed_"..id,true)
        notice(id,"notice.quest_failed")
        Events.emit("quest_failed",{quest_id=id})
        return true
    end)
end
function M.turn_in(id)
    if not enabled() or not row(id) or M.get_state(id)~="completed" then return false,"not_completed" end
    local step=row(id).steps[entry(id).step]
    if step and step.requires_flag and step.requires_flag~="" and not require("mvtk.core.flags").has(step.requires_flag) then return false,"requires_flag" end
    local Grants=require "mvtk.game.grants"
    local plan,refusal=Grants.prepare(row(id).rewards or {},{source="reward",reason="quest_turned_in",once_key="quest:"..id})
    if not plan and (not refusal or refusal.code~="already_granted") then return false,refusal end
    local changed,released=false,false
    local mark=Events.hold()
    local saved,why=require("mvtk.core.checkpoint").batch("quest_turned_in",function()
        -- Grant events remain held until the slot state and mirrors also agree.
        if plan then Grants.commit(plan) end
        local s=entry(id)
        local step=row(id).steps[s.step]
        if step and (step.complete_when or {}).turn_in and step.set_flag and step.set_flag~="" then
            local Flags=require "mvtk.core.flags"
            Flags.set(step.set_flag,true)
        end
        changed=State.turn_in(s)
        if changed then serial=serial+1 end
        local Flags=require "mvtk.core.flags"
        Flags.set("quest_turned_in_"..id,true)
        Events.emit("quest_turned_in",{quest_id=id})
        Events.release(mark) -- Downstream grants ride this outer save after state agrees.
        released=true
    end)
    -- While any hold is open the hub queues every event, so a failed batch must end it.
    if not released then Events.discard(mark) elseif changed then receive(nil,{}) end
    return changed,{saved=saved==true,save_error=why}
end
-- Text properties arrive either directly or mirrored in the registration payload.
function M.apply_trigger(trigger)
    if not enabled() then return false end
    local function prop(key)
        local value=trigger[key]
        if value==nil then value=(trigger.properties or {})[key] end
        if type(value)=="string" then value=value:match("^%s*(.-)%s*$") end
        return value~="" and value~="none" and value or nil
    end
    local Flags=require "mvtk.core.flags"
    local required,skip=prop("requires_flag"),prop("skip_if_flag")
    if required and not Flags.has(required) then return false end
    if skip and Flags.has(skip) then return false end
    local required_quest,required_state=prop("requires_quest"),prop("requires_quest_state")
    if required_quest and required_state and required_state~="any" and M.get_state(required_quest)~=required_state then return false end
    local id,action=prop("quest_id"),prop("action") or "advance"
    local changed
    if action=="start" then changed=M.start(id)
    elseif action=="advance" then changed=M.advance(id,prop("step_id"))
    elseif action=="complete" then changed=M.complete(id)
    elseif action=="fail" then changed=M.fail(id)
    else return false end
    if changed and prop("set_flag") then Flags.set(prop("set_flag"),true) end
    return changed
end

local readers={
    flag=function(id) return require("mvtk.core.flags").has(id) end,
    item=function(id) return require("mvtk.core.inventory").count(id) end,
    quest=function(id) return M.is_complete(id) end,
    level=function() return require("mvtk.game.progression.progression_manager").get_level() end,
}
local function evaluate(name,event)
    local defs=M.settings().quests or {}
    local ids={};for id in pairs(defs) do ids[#ids+1]=id end;table.sort(ids)
    local again=true
    while again do
        again=false
        for _,id in ipairs(ids) do
            local def,s=defs[id],entry(id)
            local start=def.start or {}
            if s.state=="not_started" and (start.mode=="auto" or (start.mode=="flag" and readers.flag(start.flag))) then
                State.start(s);started(id);again=true
            end
            -- A fact counts at most once, against the step current on arrival.
            local step=def.steps[s.step]
            if State.complete_turn_in(s,step,readers.flag) then
                completed(id);again=true
            elseif State.evaluate(s,step,name,event,readers) then
                local _,done=State.advance(s,def.steps);advanced(id,done);again=true
            end
        end
        name=nil;event={} -- Subsequent passes evaluate state dependencies only.
    end
end
receive=function(name,event)
    if not enabled() then return end
    pending[#pending+1]={name=name,event=event or {}}
    if busy then return end
    busy=true
    local mark=Events.hold()
    local ok,why=pcall(function()
        while #pending>0 do local e=table.remove(pending,1);evaluate(e.name,e.event) end
    end)
    -- Keep busy while held events are dispatched; those callbacks queue facts.
    if ok then Events.release(mark) else Events.discard(mark) end
    busy=false
    if not ok then pending={};error(why,0) end
    if #pending>0 then receive(nil,{}) end
end
function M.on_session_start() receive(nil,{}) end
for name in pairs(Events.EVENTS) do
    local event_name=name
    Events.on(name,function(event) receive(event_name,event) end)
end
return M
