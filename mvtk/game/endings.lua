-- Pure ending selection shared by runtime and fresh authoring checks (LuaJ-safe).
local M = {}
-- Keep the ending contract independent of the authoring model that validates it.
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = copy(item) end
    return out
end
local function merge(dst, src)
    for key, value in pairs(src or {}) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            merge(dst[key], value)
        else dst[key] = value end
    end
    return dst
end
function M.effective(baseline, overrides)
    local out = merge(copy(baseline or {}), overrides or {})
    if overrides and overrides.endings ~= nil then out.endings = copy(overrides.endings) end
    return out
end
function M.list(cfg)
    local out = {}
    if type(cfg) ~= "table" or not cfg.enabled then return out end
    for _, ending in ipairs(type(cfg.endings)=="table" and cfg.endings or {}) do
        if type(ending)=="table" and ending.enabled ~= false then out[#out+1] = ending end
    end
    out[#out+1] = cfg
    return out
end
function M.find(cfg, id)
    if not id then return nil end
    if type(cfg)~="table" then return nil end
    for _,ending in ipairs(type(cfg.endings)=="table" and cfg.endings or {}) do
        if type(ending)=="table" and ending.id==id then return ending end
    end
    if cfg.id==id then return cfg end
end
function M.ids(cfg)
    local out = {}
    for _, ending in ipairs(M.list(cfg)) do out[#out+1] = ending.id end
    return out
end
function M.trigger_met(ending, deps, regions)
    if ending.condition == "region" then return (regions or {})[ending.id] ~= nil end
    if ending.condition == "flag" then return ending.flag and ending.flag ~= "" and deps.has_flag(ending.flag) end
    if ending.condition == "boss" then return ending.boss_id and ending.boss_id ~= "" and deps.has_flag("boss_defeated_"..ending.boss_id) end
    return false
end
function M.requirements_met(ending, deps)
    local r = ending.requires or {}
    for _, flag in ipairs(r.flags or {}) do if not deps.has_flag(flag) then return false end end
    for _, boss in ipairs(r.bosses or {}) do if not deps.has_flag("boss_defeated_"..boss) then return false end end
    if r.completion_percent ~= nil then
        local percent = deps.completion_percent and deps.completion_percent()
        if percent == nil or percent < r.completion_percent then return false end
    end
    if (r.max_minutes or 0) > 0 then
        local seconds = deps.playtime_s and deps.playtime_s()
        if seconds == nil or seconds > r.max_minutes * 60 then return false end
    end
    return true
end
-- Startup-safe shape checks: catalogs and project files belong to authoring.
function M.schema_errors(cfg)
    local errors, seen = {}, {}
    if type(cfg.id)=="string" then seen[cfg.id]=true end
    local function issue(id, message) errors[#errors+1]="Ending '"..tostring(id).."': "..message end
    if cfg.requires ~= nil then issue(cfg.id,"the main ending cannot have requires") end
    if cfg.reward ~= nil and type(cfg.reward) ~= "string" then issue(cfg.id,"reward must be grant text") end
    if cfg.endings == nil then return errors end -- old flat configs remain valid
    if type(cfg.endings) ~= "table" then issue(cfg.id,"endings must be an ordered list"); return errors end
    local count=0
    for k in pairs(cfg.endings) do
        count=count+1
        if type(k)~="number" or k<1 or k%1~=0 then issue(cfg.id,"endings must be an ordered list") end
    end
    if count~=#cfg.endings then issue(cfg.id,"endings must be a contiguous ordered list") end
    for i,e in ipairs(cfg.endings) do
        if type(e)~="table" then issue(i,"must be a complete ending table")
        else
            local id=e.id
            if type(id)~="string" or not id:match("^[%w_%-]+$") then issue(id,"invalid id") end
            if type(id)=="string" and seen[id] then issue(id,"duplicate id") end
            if type(id)=="string" then seen[id]=true end
            if type(e.enabled)~="boolean" then issue(id,"enabled must be boolean") end
            for _,key in ipairs({"flag","boss_id","return_room","title","body","credits","music","artwork","reward_flag","reward"}) do
                if type(e[key])~="string" then issue(id,key.." must be text") end
            end
            if e.condition~="region" and e.condition~="flag" and e.condition~="boss" then issue(id,"invalid condition") end
            if e.condition=="flag" and e.flag=="" then issue(id,"flag trigger needs a flag") end
            if e.condition=="boss" and e.boss_id=="" then issue(id,"boss trigger needs a boss id") end
            if e.continue_policy~="completed" and e.continue_policy~="explore" then issue(id,"invalid Continue policy") end
            for _,key in ipairs({"return_x","return_y"}) do
                local n=e[key]
                if type(n)~="number" or n~=n or math.abs(n)==math.huge then issue(id,key.." must be finite") end
            end
            if e.requires~=nil and type(e.requires)~="table" then issue(id,"requires must be a table")
            else
                for key,value in pairs(e.requires or {}) do
                    if key=="flags" or key=="bosses" then
                        if type(value)~="table" then issue(id,key.." must be a text list")
                        else
                            local n=0
                            for k,v in pairs(value) do
                                n=n+1
                                if type(k)~="number" or k<1 or k%1~=0 or type(v)~="string" or v=="" then issue(id,key.." must be a text list") end
                            end
                            if n~=#value then issue(id,key.." must be a contiguous text list") end
                        end
                    elseif key=="completion_percent" or key=="max_minutes" then
                        if type(value)~="number" or value~=value or math.abs(value)==math.huge or value<0
                            or (key=="completion_percent" and value>100) then issue(id,key.." is out of range") end
                    else issue(id,"unknown requirement "..tostring(key)) end
                end
            end
        end
    end
    return errors
end
return M
