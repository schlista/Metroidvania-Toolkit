-- Pure authoring validation shared by headless Lua and the editor's LuaJ host.
local GrantSpec = require "mvtk.game.grant_spec"
local M = {}
local function text(v) return type(v)=="string" and v:match("%S")~=nil end
local function integer(v) return type(v)=="number" and v==v and v<math.huge and v>0 and v%1==0 end
local function ordered(t)
    local keys={}; for k in pairs(t) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end); return keys
end
function M.validate(cfg, events, grant_env, completion_config, ending_config)
    local errors = {}
    local function bad(id, message) errors[#errors+1]="Achievement '"..tostring(id).."': "..message end
    if type(cfg)~="table" then return {"Achievements config must be a table"} end
    for _,key in ipairs({"enabled","notify","show_hidden_count"}) do
        if type(cfg[key])~="boolean" then bad("settings",key.." must be boolean") end
    end
    if type(cfg.sfx)~="string" then bad("settings","sfx must be a sound id or blank") end
    local defs=type(cfg.achievements)=="table" and cfg.achievements or {}
    local categories=type(cfg.categories)=="table" and cfg.categories or {}
    if type(cfg.achievements)~="table" then bad("settings","achievements must be a table") end
    if type(cfg.categories)~="table" then bad("settings","categories must be a table") end
    for _,id in ipairs(ordered(categories)) do
        local row=categories[id]
        if not text(id) or type(row)~="table" or not text(row.name) then bad(id,"category needs an id and source name") end
        if type(row)=="table" and row.order~=nil and (type(row.order)~="number" or row.order~=row.order or math.abs(row.order)==math.huge) then bad(id,"category order must be finite") end
    end
    for _,id in ipairs(ordered(defs)) do
        local row=defs[id]
        if not text(id) or type(row)~="table" then bad(id,"definition needs a text id and table")
        else
            if not text(row.name) then bad(id,"name must be source text") end
            if row.description~=nil and type(row.description)~="string" then bad(id,"description must be source text") end
            if row.category~=nil and (not text(row.category) or not categories[row.category]) then bad(id,"unknown category") end
            if row.hidden~=nil and type(row.hidden)~="boolean" then bad(id,"hidden must be boolean") end
            if row.order~=nil and (type(row.order)~="number" or row.order~=row.order or math.abs(row.order)==math.huge) then bad(id,"order must be finite") end
            local t=type(row.trigger)=="table" and row.trigger or {}
            if t.type=="event" then
                local event=(events or {})[t.event]
                if not event then bad(id,"unknown event "..tostring(t.event)) end
                if not integer(t.count) then bad(id,"event count must be a positive integer") end
                if t.where~=nil and type(t.where)~="table" then bad(id,"where must be a table")
                else
                    local fields={}; for _,field in ipairs(event and event.fields or {}) do fields[field]=true end
                    for field,value in pairs(t.where or {}) do
                        if not fields[field] then bad(id,"unknown event field "..tostring(field)) end
                        local kind=type(value)
                        if kind~="string" and kind~="boolean" and kind~="number" then bad(id,"where values must be scalar")
                        elseif kind=="number" and (value~=value or math.abs(value)==math.huge) then bad(id,"where numbers must be finite") end
                    end
                end
            elseif t.type=="flag" then
                if not text(t.flag) then bad(id,"flag must be a text id") end
            elseif t.type=="item" then
                if not text(t.item) then bad(id,"item must be a text id") end
                if not integer(t.count) then bad(id,"item count must be a positive integer") end
            elseif t.type=="currency" then
                if not integer(t.amount) then bad(id,"currency amount must be a positive integer") end
            elseif t.type=="level" then
                if not integer(t.level) then bad(id,"level must be a positive integer") end
            elseif t.type=="completion" then
                if type(t.percent)~="number" or t.percent~=t.percent or t.percent<0 or t.percent>100 then bad(id,"completion percent must be from 0 to 100") end
                if t.category~=nil then
                    local categories=(completion_config or require "developer.config.completion_tracking").categories or {}
                    if not text(t.category) or not categories[t.category] then bad(id,"unknown completion category") end
                end
            elseif t.type=="ending" then
                -- Startup uses bundled settings; preparation supplies its fresh effective config.
                local cfg = ending_config or require("developer.config.runtime_settings").section(
                    "game_completion", require "developer.config.game_completion")
                local known = false
                for _, ending_id in ipairs(require("mvtk.game.endings").ids(cfg)) do
                    if ending_id == t.ending_id then known = true end
                end
                if not text(t.ending_id) or not known then bad(id,"unknown ending id "..tostring(t.ending_id)) end
                local limit = t.max_playtime_s
                if limit~=nil and (type(limit)~="number" or limit~=limit or limit<0 or limit==math.huge) then
                    bad(id,"max_playtime_s must be finite and non-negative")
                end
            elseif t.type=="quests_completed" then
                if not integer(t.count) then bad(id,"quests_completed count must be a positive integer") end
            elseif t.type=="all_of" then
                if type(t.ids)~="table" or #t.ids==0 then bad(id,"all_of needs ids")
                else
                    local seen={}
                    for index=1,#t.ids do if t.ids[index]==nil then bad(id,"all_of ids must be a dense list") end end
                    for key,ref in pairs(t.ids) do
                        if type(key)~="number" or key%1~=0 or key<1 or key>#t.ids then bad(id,"all_of ids must be a list") end
                        if not text(ref) or not defs[ref] then bad(id,"unknown all_of id "..tostring(ref))
                        elseif seen[ref] then bad(id,"duplicate all_of id "..ref) else seen[ref]=true end
                    end
                end
            else bad(id,"unknown trigger type "..tostring(t.type)) end
            if row.reward~=nil then
                -- The third argument supplies fresh authoring catalogs in editor/schema callers.
                local env={}; for key,value in pairs(grant_env or {}) do env[key]=value end
                env.once_key="achievement:"..tostring(id)
                local _,ds=GrantSpec.validate(row.reward,env)
                for _,d in ipairs(ds) do if d.severity=="error" then bad(id,"reward: "..d.message) end end
            end
        end
    end
    local visiting,done={},{}
    local function visit(id)
        if visiting[id] then bad(id,"all_of cycle"); return end
        if done[id] then return end
        visiting[id]=true
        local row=defs[id]; local t=type(row)=="table" and row.trigger
        if type(t)=="table" and t.type=="all_of" and type(t.ids)=="table" then
            for _,ref in ipairs(t.ids) do if defs[ref] then visit(ref) end end
        end
        visiting[id]=nil; done[id]=true
    end
    for _,id in ipairs(ordered(defs)) do visit(id) end
    return errors
end
return M
