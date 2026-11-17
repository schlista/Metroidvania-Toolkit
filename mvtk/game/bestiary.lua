-- Per-slot creature records. Source names belong to config; saves contain only identities and counts.
local GameEvents = require "mvtk.core.game_events"
local Checkpoint = require "mvtk.core.checkpoint"
local M = {}
local state = {species={}, bosses={}}
local serial, config_revision, config = 0

local function text(value) return type(value)=="string" and value or "" end
local function count(value)
    return type(value)=="number" and value==value and value<math.huge and math.max(0,math.floor(value)) or 0
end
local function normalized(data)
    local out = {species={}, bosses={}}
    data = type(data)=="table" and data or {}
    for _,kind in ipairs({"species", "bosses"}) do
        for id,entry in pairs(type(data[kind])=="table" and data[kind] or {}) do
            if type(id)=="string" and id~="" and type(entry)=="table" then
                local row = {defeats=count(entry.defeats)}
                if kind=="species" then
                    for _,key in ipairs({"skin", "enemy_type", "archetype"}) do row[key]=text(entry[key]) end
                end
                out[kind][id] = row
            end
        end
    end
    return out
end

function M.settings()
    local Runtime = require "developer.config.runtime_settings"
    local revision = Runtime.revision()
    if config == nil or config_revision ~= revision then
        config = Runtime.section("bestiary", require "developer.config.bestiary")
        config_revision = revision
    end
    return config
end
function M.revision() return serial end
function M.snapshot() return normalized(state) end

-- Returns distinct recorded and possible identities in the supplied census entries.
-- Recorded identities outside this census stay in snapshot(), but never inflate totals.
function M.progress(entries)
    local cfg, species, bosses = M.settings(), {}, {}
    for _,entry in ipairs(entries or {}) do
        if entry.kind=="enemy" and entry.in_bestiary~=false then
            for _,id in ipairs(entry.species or {}) do if type(id)=="string" and id~="" then species[id]=true end end
            if cfg.include_spawned~=false then
                for _,id in ipairs(entry.spawn_species or {}) do if type(id)=="string" and id~="" then species[id]=true end end
            end
        elseif entry.kind=="boss" and cfg.include_bosses~=false then
            if type(entry.preset)=="string" and entry.preset~="" then bosses[entry.preset]=true end
        end
    end
    local recorded, total = 0, 0
    for _,bucket in ipairs({{species,state.species}, {bosses,state.bosses}}) do
        for id in pairs(bucket[1]) do
            total=total+1
            if (bucket[2][id] or {}).defeats and bucket[2][id].defeats>0 then recorded=recorded+1 end
        end
    end
    return recorded, total
end

local function notice(kind, id, cfg)
    if cfg.enabled~=true or cfg.notify_new_entry~=true then return end
    local entry = (cfg[kind=="species" and "entries" or "bosses"] or {})[id] or {}
    require("mvtk.ui.notices").post({kind="bestiary", title={key="bestiary.new_entry"},
        text=type(entry.name)=="string" and entry.name:match("%S") and entry.name or {key="list.missing_name"},
        key="bestiary_"..id})
end
GameEvents.on("enemy_defeated", function(event)
    local cfg = M.settings()
    if event.in_bestiary==false or (event.spawned==true and cfg.include_spawned==false) then return end
    local id = text(event.species)
    if id=="" then return end
    local row = state.species[id] or {defeats=0,skin="",enemy_type="",archetype=""}
    local first = row.defeats==0
    row.defeats=row.defeats+1
    -- Keep the last skin for which the generated manifest has an identity.
    local skins = require "developer.config.enemy_skins_generated"
    if ((skins.skins or skins)[text(event.skin)]) then row.skin=event.skin end
    row.enemy_type, row.archetype = text(event.enemy_type), text(event.archetype)
    state.species[id], serial = row, serial+1
    if first then notice("species", id, cfg) end
end)
GameEvents.on("boss_defeated", function(event)
    local cfg, id = M.settings(), text(event.preset)
    if cfg.include_bosses==false or id=="" then return end
    local row = state.bosses[id] or {defeats=0}
    local first = row.defeats==0
    row.defeats=row.defeats+1
    state.bosses[id], serial = row, serial+1
    if first then notice("bosses", id, cfg) end
end)
Checkpoint.register_provider("bestiary", {version=1, order=220,
    capture=function() return normalized(state) end,
    apply=function(data) state=normalized(data); serial=serial+1 end,
    defaults=function() state=normalized(nil); serial=serial+1 end,
})
return M
