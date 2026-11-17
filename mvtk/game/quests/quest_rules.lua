-- Pure authoring checks shared by startup, headless Lua and editor LuaJ.
local GrantSpec = require "mvtk.game.grant_spec"
local GameEvents = require "mvtk.core.game_events"
local M = {}
local function text(v) return type(v)=="string" and v:match("%S")~=nil end
local function integer(v) return type(v)=="number" and v==v and v<math.huge and v>0 and v%1==0 end
local function keys(t)
    local out={};for k in pairs(t) do out[#out+1]=k end
    table.sort(out,function(a,b) return tostring(a)<tostring(b) end);return out
end
local function list(t)
    if type(t)~="table" or #t==0 then return false end
    for k in pairs(t) do if type(k)~="number" or k%1~=0 or k<1 or k>#t then return false end end
    for i=1,#t do if t[i]==nil then return false end end
    return true
end
function M.validate(cfg,grant_env)
    local errors={}
    local function bad(id,message) errors[#errors+1]="Quest '"..tostring(id).."': "..message end
    if type(cfg)~="table" then return {"Quests config must be a table"} end
    if type(cfg.enabled)~="boolean" then bad("settings","enabled must be boolean") end
    local defs=type(cfg.quests)=="table" and cfg.quests or {}
    local categories=type(cfg.categories)=="table" and cfg.categories or {}
    if type(cfg.quests)~="table" then bad("settings","quests must be a table") end
    if type(cfg.categories)~="table" then bad("settings","categories must be a table") end
    for _,id in ipairs(keys(categories)) do
        local c=categories[id]
        if not text(id) or type(c)~="table" or not text(c.name) then bad(id,"category needs source name") end
        if type(c)=="table" and c.order~=nil and (type(c.order)~="number" or c.order~=c.order or math.abs(c.order)==math.huge) then bad(id,"category order must be finite") end
    end
    for _,id in ipairs(keys(defs)) do
        local row=defs[id]
        if not text(id) or type(row)~="table" then bad(id,"definition needs a text id and table")
        else
            if not text(row.title) then bad(id,"title must be nonblank source text") end
            for _,field in ipairs({"description","giver"}) do if row[field]~=nil and type(row[field])~="string" then bad(id,field.." must be source text") end end
            if row.category~=nil and not categories[row.category] then bad(id,"unknown category") end
            if row.hidden_until_started~=nil and type(row.hidden_until_started)~="boolean" then bad(id,"hidden_until_started must be boolean") end
            local start=type(row.start)=="table" and row.start or {}
            if not ({auto=true,flag=true,dialogue=true,trigger=true})[start.mode] then bad(id,"unknown start mode") end
            if start.mode=="flag" and not text(start.flag) then bad(id,"flag start needs flag") end
            if not list(row.steps) then bad(id,"steps must be a nonempty dense list") end
            local seen={}
            for n,step in ipairs(type(row.steps)=="table" and row.steps or {}) do
                if type(step)~="table" then bad(id,"step must be a table")
                else
                    if not text(step.id) or seen[step.id] then bad(id,"step needs a unique text id") else seen[step.id]=true end
                    if not text(step.text) then bad(id,"step text must be nonblank source text") end
                    for _,field in ipairs({"requires_flag","set_flag"}) do if step[field]~=nil and type(step[field])~="string" then bad(id,field.." must be text") end end
                    local goal=type(step.complete_when)=="table" and step.complete_when or {}
                    local forms=0
                    for _,key in ipairs({"flag","item","event","trigger","turn_in","quest","level"}) do if goal[key]~=nil then forms=forms+1 end end
                    if forms~=1 then bad(id,"complete_when needs exactly one objective") end
                    for key in pairs(goal) do if not ({flag=true,item=true,event=true,trigger=true,turn_in=true,quest=true,level=true,count=true,where=true})[key] then bad(id,"unknown objective field "..tostring(key)) end end
                    for _,field in ipairs({"flag","item","quest"}) do if goal[field]~=nil and not text(goal[field]) then bad(id,field.." objective needs text id") end end
                    if goal.quest and not defs[goal.quest] then bad(id,"unknown quest objective") end
                    if goal.level~=nil and not integer(goal.level) then bad(id,"level must be a positive integer") end
                    if goal.trigger~=nil and goal.trigger~=true then bad(id,"trigger must be true") end
                    if goal.turn_in~=nil then
                        if goal.turn_in~=true then bad(id,"turn_in must be true") end
                        if n~=#row.steps then bad(id,"turn-in step must be last") end
                    end
                    if (goal.event or goal.item) and goal.count~=nil and not integer(goal.count) then bad(id,"count must be a positive integer") end
                    if goal.event~=nil then
                        local event=GameEvents.EVENTS[goal.event]
                        if not event then bad(id,"unknown event "..tostring(goal.event)) end
                        if goal.where~=nil and type(goal.where)~="table" then bad(id,"where must be a table")
                        else
                            local fields={};for _,f in ipairs(event and event.fields or {}) do fields[f]=true end
                            for f,v in pairs(goal.where or {}) do
                                if not fields[f] then bad(id,"unknown event field "..tostring(f)) end
                                local kind=type(v)
                                if kind~="string" and kind~="number" and kind~="boolean" then bad(id,"where values must be scalar")
                                elseif kind=="number" and (v~=v or math.abs(v)==math.huge) then bad(id,"where numbers must be finite") end
                            end
                        end
                    end
                end
            end
            if row.rewards~=nil then
                local env={};for k,v in pairs(grant_env or {}) do env[k]=v end
                env.once_key="quest:"..tostring(id)
                local _,ds=GrantSpec.validate(row.rewards,env)
                for _,d in ipairs(ds) do if d.severity=="error" then bad(id,"rewards: "..d.message) end end
            end
        end
    end
    return errors
end
return M
