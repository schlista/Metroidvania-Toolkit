-- Pure transitions: no settings, events, flags, grants or engine dependencies.
local M = {}
M.STATES = {not_started=true, active=true, completed=true, turned_in=true, failed=true}
local function whole(n)
    return type(n)=="number" and n==n and n<math.huge and math.max(0,math.floor(n)) or 0
end
function M.normalize(data)
    data=type(data)=="table" and data or {}
    local out={state=M.STATES[data.state] and data.state or "not_started", step=whole(data.step), counters={}}
    for id,n in pairs(type(data.counters)=="table" and data.counters or {}) do
        if type(id)=="string" then out.counters[id]=whole(n) end
    end
    if out.state=="not_started" then out.step=0; out.counters={} end
    return out
end
function M.start(state)
    if state.state~="not_started" then return false end
    state.state,state.step="active",1
    return true
end
function M.advance(state,steps,step_id)
    if state.state~="active" then return false end
    local step=steps[state.step]
    if not step or (step_id and step_id~="" and step.id~=step_id) then return false end
    state.step=state.step+1
    local next_step=steps[state.step]
    if not next_step then state.state="completed" end
    return true,step
end
-- A turn-in objective is ready only after its own guard is satisfied.
-- Inject the flag reader to keep all transitions independent of runtime services.
function M.complete_turn_in(state,step,flag)
    if state.state~="active" or not step or not (step.complete_when or {}).turn_in then return false end
    if step.requires_flag and step.requires_flag~="" and not flag(step.requires_flag) then return false end
    state.state="completed"
    return true
end
function M.complete(state)
    if state.state~="active" then return false end
    state.state="completed"
    return true
end
function M.turn_in(state)
    if state.state~="completed" then return false end
    state.state="turned_in"
    return true
end
function M.fail(state)
    if state.state~="active" and state.state~="completed" then return false end
    state.state="failed"
    return true
end
function M.evaluate(state,step,name,event,read)
    if state.state~="active" or not step then return false end
    if step.requires_flag and step.requires_flag~="" and not read.flag(step.requires_flag) then return false end
    local goal=step.complete_when or {}
    if goal.event then
        if name~=goal.event or (name=="gate_opened" and event.temporary==true) then return false end
        for key,value in pairs(goal.where or {}) do if event[key]~=value then return false end end
        state.counters[step.id]=math.min(goal.count or 1,(state.counters[step.id] or 0)+1)
        return state.counters[step.id]>=(goal.count or 1)
    end
    if goal.flag then return read.flag(goal.flag) end
    if goal.item then return read.item(goal.item)>=(goal.count or 1) end
    if goal.quest then return read.quest(goal.quest) end
    if goal.level then return read.level()>=goal.level end
    return false -- Trigger and turn-in objectives require explicit actions.
end
return M
