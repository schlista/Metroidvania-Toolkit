-- Derived progress only: no save provider and no engine calls from hub listeners.
local Events = require "mvtk.core.game_events"
local M = {}
local config, settings_revision, cache
local previous, initialized
local starting=true
local builtins = {upgrades=true,bosses=true,map=true,secrets=true,chests=true,
    collection=true,quests=true,bestiary=true,guardians=true,trials=true}

function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if config==nil or settings_revision~=revision then
        config = Runtime.section("completion_tracking",require "developer.config.completion_tracking")
        settings_revision = revision
        cache = nil
    end
    return config
end
local function contains(values,value)
    for _,v in ipairs(values or {}) do if v==value then return true end end
    return false
end
local function weighted(cfg,id)
    return (((cfg.categories or {})[id] or {}).weight or 0)>0
end
local function progress(id,rule,Census,entries)
    if id=="map" then
        local Discovery = require "mvtk.map.discovery"
        local found,total=0,0
        for _,room in ipairs(require("mvtk.map.streaming.room_manager").list_rooms()) do
            total=total+1; if Discovery.is_visited(room) then found=found+1 end
        end
        return found,total
    elseif id=="quests" then
        local Quests = require "mvtk.game.quests.quests"
        local found,total=0,0
        for quest in pairs(Quests.settings().quests or {}) do
            total=total+1; if Quests.is_complete(quest) then found=found+1 end
        end
        return found,total
    elseif id=="bestiary" then
        return require("mvtk.game.bestiary").progress(entries)
    elseif id=="guardians" or id=="trials" then
        local found,total=0,0
        for _,entry in ipairs(entries) do
            if (id=="guardians" and entry.kind=="enemy" and entry.guardian==true) or (id=="trials" and entry.kind=="trial") then
                total=total+1; if Census.state(entry) then found=found+1 end
            end
        end
        return found,total
    end
    local Types = require "developer.config.collectible_types"
    local kinds={bosses="boss",secrets="secret",chests="chest"}
    local totals=Census.totals(function(entry)
        if entry.kind=="item" then return contains(rule.collectible_categories,(Types[entry.type] or {}).category) end
        return (kinds[id]~=nil and entry.kind==kinds[id]) or (rule.lore_items==true and entry.kind=="lore")
    end)
    return totals.found,totals.total
end
local function current()
    local cfg=M.settings()
    if cfg.enabled~=true then return nil,{} end
    local Census = require "mvtk.world.census"
    local Quests = require "mvtk.game.quests.quests"
    local Bestiary = require "mvtk.game.bestiary"
    local cr,qr,br=Census.revision(),Quests.revision(),Bestiary.revision()
    if not cache or cache.cr~=cr or cache.qr~=qr or cache.br~=br then
        local entries,rows=Census.entries(),{}
        local sum,weights=0,0
        for id,rule in pairs(cfg.categories or {}) do
            local found,total=progress(id,rule,Census,entries)
            rows[#rows+1]={id=id,found=found,total=total,weight=rule.weight,order=rule.order or 0}
            if rule.weight>0 and total>0 then sum=sum+rule.weight*found/total; weights=weights+rule.weight end
        end
        table.sort(rows,function(a,b) if a.order~=b.order then return a.order<b.order end; return a.id<b.id end)
        local percent
        if weights>0 then percent=math.floor(100*sum/weights+(cfg.rounding=="round" and 0.5 or 0)) end
        cache={cr=cr,qr=qr,br=br,percent=percent,rows=rows}
    end
    return cache.percent,cache.rows
end
function M.percent() local percent=current(); return percent end
function M.breakdown()
    local _,rows=current(); local out={}
    for _,row in ipairs(rows) do out[#out+1]={id=row.id,found=row.found,total=row.total,weight=row.weight} end
    return out
end
function M.ending_snapshot()
    local cfg=M.settings()
    if cfg.enabled==true and cfg.show_on_ending==true then return M.percent() end
end
function M.section()
    return {id="completion",order=20,
        visible=function() local cfg=M.settings(); return cfg.enabled==true and cfg.show_in_journal==true end,
        header=function() return {key="records.completion"} end,
        summary=function()
            local percent=M.percent()
            return percent~=nil and {key="records.summary",params={count=percent}} or {key="records.percent_unknown"}
        end,
        lines=function()
            local rows={}
            for _,row in ipairs(M.breakdown()) do
                local rule=M.settings().categories[row.id]
                local label=builtins[row.id] and {key="records.category."..row.id}
                    or (type(rule.label)=="string" and rule.label:find("%S") and rule.label or {key="list.missing_name"})
                rows[#rows+1]={label=label,value={forms={one="journal.progress_one",other="journal.progress_other"},
                    count=row.total,params={found=row.found,total=row.total}}}
            end
            return rows
        end}
end
function M.before_session_start()
    starting=true
    cache=nil
    previous=nil
    initialized=false
end
function M.on_session_start()
    cache=nil
    previous=M.percent(); initialized=true -- Apply/defaults and session restore stay silent.
    starting=false
    require("mvtk.ui.screens.journal_records").add_section(M.section())
end
local function changed()
    if starting or M.settings().enabled~=true then return end
    local percent=M.percent()
    local before=previous
    previous=percent
    if initialized and percent~=before then Events.emit("completion_changed",{percent=percent,previous=before}) end
    initialized=true
end
for _,name in ipairs({"collectible_collected","chest_opened","secret_found","boss_defeated","room_visited"}) do Events.on(name,changed) end
for _,name in ipairs({"quest_started","quest_step","quest_completed","quest_turned_in","quest_failed"}) do
    Events.on(name,function()
        local cfg=M.settings()
        if cfg.enabled==true and weighted(cfg,"quests") then changed() end
    end)
end
Events.on("enemy_defeated",function(event)
    local cfg=M.settings()
    if cfg.enabled~=true then return end
    if weighted(cfg,"guardians") and event.respawn=="never" then changed(); return end
    if weighted(cfg,"bestiary") then
        local species=require("mvtk.game.bestiary").snapshot().species
        if (species[event.species] or {}).defeats==1 then changed() end
    end
end)
Events.on("trial_completed",function()
    local cfg=M.settings()
    if cfg.enabled==true and weighted(cfg,"trials") then changed() end
end)
-- Placed Lore Items publish their collected flag, rather than a collectible fact.
Events.on("flag_set",function(event)
    if type(event.flag)~="string" or event.flag:sub(1,#"collected_lore_")~="collected_lore_" then return end
    local cfg=M.settings()
    if cfg.enabled~=true then return end
    for _,rule in pairs(cfg.categories or {}) do
        if rule.weight>0 and rule.lore_items==true then changed(); return end
    end
end)
return M
