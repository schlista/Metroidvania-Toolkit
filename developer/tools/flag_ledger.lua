-- Pure cross-content flag inventory. Also runs in the editor's LuaJ sandbox.
local BossIdentity = require "mvtk.bosses.boss_identity"
local GrantSpec = require "mvtk.game.grant_spec"
local Properties = require "mvtk.tiled.property_flattener"
local PresenceCondition = require "mvtk.world.presence_condition"
local M = {}
M.FIELDS = {
    clear_flag="effective",
    stage_flags="list_reader",
    vendor_flag="reader",
    requires_flag="reader", skip_if_flag="reader", despawn_flag="reader",
    set_flag="writer", set_flag_off="writer", set_flag_on_collect="writer",
    unlock_flag="writer", destroy_flag="writer", once_flag="both", set_flag_on="both",
    reward_unlock_flag="effective", defeat_flag="effective",
    -- World-state conditions (G8-09): every flag the text names is read there.
    appear_when="condition", remove_when="condition",
}
-- Every source row owns its runtime setter(s); the source census tests tie
-- literal and variable-key calls to these rows rather than guessing from names.
M.CONFIG_SOURCES = {
    crafting="recipe requires_flag readers",
    quests="start.flag and step requires_flag/complete_when.flag readers; step.set_flag writers; rewards through configs.grants",
    goals="done_when flags, counts and any (recursive) readers; goal_announced_, goal_finished_, goal_revealed_ and goal_hint_paid_ mirrors",
    countdowns="countdowns.*.start_when condition readers; finish_flag writers (blank: countdown_cleared_<id>); rewards through configs.grants",
    achievements="achievements.*.trigger.flag readers; reward grant-text writers through configs.grants",
    extras="jukebox.tracks.*.unlock.flag and gallery.entries.*.unlock.flag readers (type flag); Extras never writes flags",
    leveling="enabled milestones.*.set_flag writers",
    shops="catalog entries: requires_flag reader; set_flag and flag:<name> gives writer",
    dialogues="condition.flag; line/choice set_flag; reachable next/goto chains",
    completion="enabled endings: flag/boss trigger and requires readers; reward_flag and reward grant writers",
    bosses="placed preset on_defeat.unlock_flag, after authored overrides",
    tutorials="popups.*.trigger_flag is read and written",
    secrets="visible policy: reveal_flag, wall_id hash, or secret_<entry key>",
    grants="flag:<name>, fast_travel:<id>, set_flags and grant_once:<key>",
    map_icons="item_tracking.require_flag and kinds.*.rule flag:<name> readers",
    biomes="region_seen_<region> first-visit mirrors for every biomes.lua entry",
}
M.SYSTEM_WRITERS = {
    assist_used="assist_used", assist_slowed="assist_slowed",
    trial="trial_cleared_", trial_rank="trial_rank_", trial_best="trial_best_",
    quest_started="quest_started_", quest_completed="quest_completed_", quest_turned_in="quest_turned_in_", quest_failed="quest_failed_",
    goal_announced="goal_announced_", goal_finished="goal_finished_", goal_revealed="goal_revealed_", goal_hint_paid="goal_hint_paid_",
    countdown_active="countdown_<id>_active", countdown_best="countdown_best_", countdown_cleared="countdown_cleared_",
    region_seen="region_seen_", room_title_seen="room_title_seen_",
    altar_used="altar_used:",
    npc_greeted="npc_greeted:",
    shop_sold="shop_sold:",
    fragment_count="fragment_count_", fragment_piece="fragment_piece_",
    encounter="encounter_cleared_",
    enemy_defeat="enemy_defeated_",
    carry_placed="carry_placed_",
    cutscene_opening="cutscene_seen_opening", cutscene_boss="cutscene_seen_boss_",
    dev_tools="developer-entered flag name, inside the save sandbox only",
    ability="ability ids", boss="boss_defeated_", fast_travel="fast_travel_",
    collectible="collected_", relic="collected_relic_", relic_data="relic_data_",
    lore="collected_lore_", lore_title="lore_title_", lore_text="lore_text_", lore_category="lore_category_",
    secret="secret_", gate="gate_", gate_seq="gate_seq_", gate_timer="gate_timer_",
    gate_group="gate_group_",
    door="door id", map="map_revealed_", map_station="map_station_used_",
    trigger="mvtk_trigger_once_", grant_once="grant_once:",
    chest="chest_opened_", wall="wall_broken_", prop_broken="prop_broken_",
    switch_state="switch_state_", switch_channel="switch_channel_",
}
local function id(value)
    if type(value)~="string" then return nil end
    return value~="" and value or nil
end
local function trimmed(value)
    return type(value)=="string" and id(value:match("^%s*(.-)%s*$")) or nil
end
local function cutscene_optional(value)
    local text=trimmed(value)
    if text~="none" then return text end
end
function M.effective_boss_flag(props, preset)
    props=props or {}; preset=preset or {}
    return trimmed(props.reward_unlock_flag) or trimmed(props.defeat_flag)
        or trimmed(type(preset.on_defeat)=="table" and preset.on_defeat.unlock_flag)
end
local function distance(a,b)
    local prev={}; for j=0,#b do prev[j]=j end
    for i=1,#a do
        local row={[0]=i}
        for j=1,#b do
            row[j]=math.min(row[j-1]+1,prev[j]+1,prev[j-1]+(a:byte(i)==b:byte(j) and 0 or 1))
        end
        prev=row
    end
    return prev[#b]
end
local function allowed(name, allow)
    for _,pattern in ipairs(allow or {}) do
        if type(pattern)=="string" and (name==pattern or
            (pattern:sub(-2)=="_*" and name:sub(1,#pattern-1)==pattern:sub(1,-2))) then return true end
    end
    return false
end
local function fragment(value)
    local s=tostring(value):lower():gsub("[^%w_]+","_"):gsub("_+","_"):gsub("^_+",""):gsub("_+$","")
    return s~="" and s or "unknown"
end
local function config_location(file, property)
    return {file="developer/config/"..file,property=property}
end

function M.check(index, configs, lint)
    configs=configs or {}; lint=(lint or {}).flags or {}
    local reads,writes,ds={},{},{}
    local function issue(entry,code,severity,message,fix)
        local d={}; for k,v in pairs(entry.location) do d[k]=v end
        d.code,d.severity,d.message,d.fix=code,severity,message,fix
        ds[#ds+1]=d
    end
    local function add(name, mode, location, system, inactive)
        name=id(name); if not name then return end
        local entry={name=name,location=location or {},inactive=inactive,system=system or mode=="both"}
        if name=="none" then
            issue(entry,"flag_none_literal",inactive and "info" or lint.errors==true and "error" or "warning",
                "Flag '"..name.."' is literal here and will not unlock this object.",
                "Clear the flag field; baked dialogue and cutscene triggers treat none as blank.")
            return
        end
        if mode=="reader" or mode=="both" then reads[#reads+1]=entry end
        if (mode=="writer" or mode=="both") and not inactive then
            writes[name]=writes[name] or {}; writes[name][#writes[name]+1]=entry
        end
    end
    for _, key in ipairs({"assist_used", "assist_slowed"}) do
        add(M.SYSTEM_WRITERS[key], "writer", {file="mvtk/player/assist.lua", property=key}, true)
    end
    local function system(prefix, key, location) if id(key) then add(prefix..key,"both",location,true) end end
    local function grant(value, location, opts)
        local entries=GrantSpec.parse(value)
        for _,entry in ipairs(entries) do
            if entry.kind=="flag" then add(entry.id,"writer",location)
            elseif entry.kind=="fast_travel" then system("fast_travel_",entry.id,location) end
        end
        opts=opts or {}
        for key in pairs(opts.set_flags or {}) do add(key,"writer",location) end
        system("grant_once:",opts.once_key,location)
    end
    -- Custom grant owners can supply the same grammar/options used at runtime.
    for _,row in ipairs(configs.grants or {}) do grant(row.give,row.location,row) end
    for catalog_id,catalog in pairs((configs.shops or {}).catalogs or {}) do
        for _,entry in ipairs(catalog.entries or {}) do
            local path="catalogs."..catalog_id..".entries."..entry.id
            add(entry.requires_flag,"reader",config_location("shops.lua",path..".requires_flag"))
            system("shop_sold:",catalog_id..":"..entry.id,config_location("shops.lua",path))
        end
    end
    local leveling = configs.leveling or {}
    for level, milestone in pairs(leveling.milestones or {}) do
        if type(milestone)=="table" then
            add(milestone.set_flag,"writer",config_location("leveling.lua","milestones."..tostring(level)..".set_flag"),false,not leveling.enabled)
        end
    end
    for i,recipe in ipairs((configs.crafting or {}).recipes or {}) do
        add(recipe.requires_flag,"reader",config_location("crafting.lua","recipes."..i..".requires_flag"),false,(configs.crafting or {}).enabled~=true)
    end
    local quests=configs.quests or {}
    for key,row in pairs(type(quests.quests)=="table" and quests.quests or {}) do
        if type(row)=="table" then
            local location=config_location("quests.lua","quests."..tostring(key))
            for _,prefix in ipairs({"quest_started_","quest_completed_","quest_turned_in_","quest_failed_"}) do system(prefix,key,location) end
            local inactive=quests.enabled~=true
            local start=type(row.start)=="table" and row.start or {}
            if start.mode=="flag" then add(start.flag,"reader",config_location("quests.lua","quests."..tostring(key)..".start.flag"),false,inactive) end
            for n,step in ipairs(type(row.steps)=="table" and row.steps or {}) do
                if type(step)=="table" then
                    local path="quests."..tostring(key)..".steps."..n
                    add(step.requires_flag,"reader",config_location("quests.lua",path..".requires_flag"),false,inactive)
                    add(step.set_flag,"writer",config_location("quests.lua",path..".set_flag"),false,inactive)
                    add((type(step.complete_when)=="table" and step.complete_when or {}).flag,"reader",config_location("quests.lua",path..".complete_when.flag"),false,inactive)
                end
            end
        end
    end
    local goals=configs.goals or {}
    for n,row in ipairs(type(goals.goals)=="table" and goals.goals or {}) do
        if type(row)=="table" then
            local path="goals."..n
            -- Hint Stones (mvtk/prefabs/hint_goal.lua) write the reveal and paid mirrors.
            for _,prefix in ipairs({"goal_announced_","goal_finished_","goal_revealed_","goal_hint_paid_"}) do
                system(prefix,type(row.id)=="string" and row.id or nil,config_location("goals.lua",path..".id"))
            end
            local inactive=goals.enabled~=true
            local function requirement(req,at)
                if type(req)~="table" then return end
                for name in pairs(type(req.flags)=="table" and req.flags or {}) do
                    add(name,"reader",config_location("goals.lua",at..".flags."..tostring(name)),false,inactive)
                end
                for c,count in ipairs(type(req.counts)=="table" and req.counts or {}) do
                    for _,name in ipairs(type(count)=="table" and type(count.flags)=="table" and count.flags or {}) do
                        add(name,"reader",config_location("goals.lua",at..".counts."..c..".flags"),false,inactive)
                    end
                end
                for a,alternative in ipairs(type(req.any)=="table" and req.any or {}) do requirement(alternative,at..".any."..a) end
            end
            requirement(row.done_when,path..".done_when")
        end
    end
    -- Countdowns (mvtk/game/countdown.lua): every configured id runs with its
    -- active flag and may save a best time; the finish flag is authored or derived.
    local countdowns=configs.countdowns or {}
    for key,row in pairs(type(countdowns.countdowns)=="table" and countdowns.countdowns or {}) do
        if type(key)=="string" and type(row)=="table" then
            local path="countdowns."..key
            local location=config_location("countdowns.lua",path)
            add("countdown_"..key.."_active","both",location,true)
            system("countdown_best_",key,location)
            local finish=trimmed(row.finish_flag)
            if finish then add(finish,"writer",config_location("countdowns.lua",path..".finish_flag"))
            else system("countdown_cleared_",key,location) end
            if type(row.start_when)=="string" then
                for _,name in ipairs(PresenceCondition.flags(row.start_when) or {}) do
                    add(name,"reader",config_location("countdowns.lua",path..".start_when"))
                end
            end
        end
    end
    -- Title cards (mvtk/ui/region_titles.lua): one first-visit mirror per region,
    -- and one per room whose map properties ask for a landmark card.
    for key in pairs(type(configs.biomes)=="table" and configs.biomes or {}) do
        if type(key)=="string" then system("region_seen_",key,config_location("biomes.lua",key)) end
    end
    for room,props in pairs(type(configs.map_properties)=="table" and configs.map_properties or {}) do
        if type(room)=="string" and type(props)=="table" and trimmed(props.room_title)
            and (props.room_title_card==true or props.room_title_card=="true") then
            system("room_title_seen_",room,{room=room,property="room_title_card"})
        end
    end
    local map_icons=type(configs.map_icons)=="table" and configs.map_icons or {}
    local tracking=type(map_icons.item_tracking)=="table" and map_icons.item_tracking or {}
    add(tracking.require_flag,"reader",config_location("map_icons.lua","item_tracking.require_flag"),false,tracking.enabled==false)
    for key,row in pairs(type(map_icons.kinds)=="table" and map_icons.kinds or {}) do
        local flag=type(row)=="table" and type(row.rule)=="string" and row.rule:match("^flag:(.+)$")
        if flag then add(flag,"reader",config_location("map_icons.lua","kinds."..tostring(key)..".rule")) end
    end
    local achievements=configs.achievements or {}
    for key,row in pairs(type(achievements.achievements)=="table" and achievements.achievements or {}) do
        local trigger=type(row)=="table" and row.trigger
        if type(trigger)=="table" and trigger.type=="flag" then
            add(trigger.flag,"reader",config_location("achievements.lua",key..".trigger.flag"),false,achievements.enabled~=true)
        end
    end
    local extras=configs.extras or {}
    for _,kind in ipairs({{"jukebox","tracks"},{"gallery","entries"}}) do
        local section=type(extras[kind[1]])=="table" and extras[kind[1]] or {}
        local inactive=extras.enabled~=true or section.enabled==false
        for i,row in ipairs(type(section[kind[2]])=="table" and section[kind[2]] or {}) do
            local unlock=type(row)=="table" and row.unlock
            if type(unlock)=="table" and unlock.type=="flag" then
                add(unlock.flag,"reader",config_location("extras.lua",kind[1].."."..kind[2].."."..i..".unlock.flag"),false,inactive)
            end
        end
    end
    local dialogue_roots={}
    for _,ref in ipairs(index.references or {}) do
        local from=ref.from or {}
        if ref.namespace=="dialogue" and ref.key and from.visible~=false and from.top_level~=false then
            dialogue_roots[ref.key]=true
        end
    end
    for _,o in ipairs(index.objects or {}) do
        local p=o.properties or {}
        if o.visible~=false and o.top_level~=false then
            for field,mode in pairs(M.FIELDS) do
                if mode~="ignore" and (mode~="effective" or p[field]=="none") then
                    local value=p[field]
                    if o.type=="cutscene" then value=cutscene_optional(value)
                    elseif o.type=="dialogue_trigger" and value=="none" then value=nil end
                    local location={file=o.file,room=o.room,layer=o.layer,object_id=o.object_id,property=field}
                    if mode=="list_reader" then
                        for token in tostring(value or ""):gmatch("[^,]+") do
                            add(trimmed(token),"reader",location)
                        end
                    elseif mode=="condition" then
                        -- Text that does not parse is content_checks'
                        -- presence_condition_invalid error, reported once there.
                        for _,name in ipairs(type(value)=="string" and PresenceCondition.flags(value) or {}) do
                            add(name,"reader",location)
                        end
                    else
                        add(value,field=="set_flag" and o.type=="torch_holder" and "both" or mode,location)
                    end
                end
            end
            local loc={file=o.file,room=o.room,layer=o.layer,object_id=o.object_id}
            local function sys(prefix,key) system(prefix,key,loc) end
            if (o.type=="lever" or o.type=="pressure_plate" or o.type=="strike_switch") and p.persist_state==true
                and not (o.type=="strike_switch" and (trimmed(p.mode)=="timed" or trimmed(p.mode)=="momentary"))
                and not (o.type=="lever" and (p.toggle==false or trimmed(p.message_on)=="elevator_call_bottom"
                    or trimmed(p.message_on)=="elevator_call_top")) then
                sys("switch_state_",trimmed(p.persist_key) or (o.room.."_"..o.object_id))
                local target=trimmed(p.target_id)
                if not target and o.type=="pressure_plate" then
                    target=trimmed(p.plate_id) or trimmed(o.name) or ("plate_"..o.room.."_"..o.object_id)
                end
                sys("switch_channel_",target)
            elseif o.type=="breakable_prop" and p.stays_broken==true then
                sys("prop_broken_",trimmed(p.prop_id) or o.instance_id)
                sys("switch_channel_",trimmed(p.target_id))
            elseif o.type=="timed_door" and p.stays_open==true then
                local channel=trimmed(p.door_id) or trimmed(o.name) or ("door_"..o.room.."_"..o.object_id)
                sys("switch_channel_",channel)
                sys("switch_state_","timed_door:"..channel)
            end
            if p.dialogue_id then dialogue_roots[p.dialogue_id]=true end
            if o.type=="npc" then
                local def=(configs.npc_types or {})[trimmed(p.npc_type)] or {}
                local root=trimmed(p.dialogue_id) or trimmed(def.dialogue_id)
                if root then dialogue_roots[root]=true end
            elseif o.type=="encounter" and p.repeatable~=true then
                local key=trimmed(p.encounter_id) or o.instance_id
                loc.property="clear_flag"
                add(trimmed(p.clear_flag) or ("encounter_cleared_"..key),"both",loc,true)
                sys("switch_channel_",trimmed(p.target_id))
            elseif o.type=="combat_trial" then
                local key=trimmed(p.trial_id) or o.instance_id
                loc.property="clear_flag"
                add(id(p.clear_flag) or ("trial_cleared_"..key),"both",loc,true)
                sys("trial_rank_",key)
                sys("trial_best_",key)
                grant(p.trial_reward,{file=o.file,room=o.room,layer=o.layer,object_id=o.object_id,property="trial_reward"},
                    {once_key="trial:"..key})
            elseif o.type=="offering_altar" then
                local reward_loc={file=o.file,room=o.room,layer=o.layer,object_id=o.object_id,property="reward"}
                grant(p.reward,reward_loc)
                -- Match the bake: preserve a nonblank id verbatim; none is optional.
                local altar_id=type(p.altar_id)=="string" and p.altar_id or ""
                local optional=altar_id:match("^%s*(.-)%s*$")
                if optional=="" or optional=="none" then altar_id=o.instance_id end
                sys("altar_used:",altar_id)
            elseif o.type=="enemy" then
                loc.property="defeat_flag"
                add(trimmed(p.defeat_flag),"both",loc)
                sys("enemy_defeated_",o.instance_id)
                if p.champion == true and trimmed(p.champion_reward) then
                    local reward_loc={file=o.file,room=o.room,layer=o.layer,object_id=o.object_id,property="champion_reward"}
                    local key=require("mvtk.enemies.enemy_respawn_policy").persist_key(p.defeat_flag,o.instance_id)
                    grant(p.champion_reward,reward_loc,{once_key="champion:"..key})
                end
            elseif o.type=="boss" then
                local preset=(configs.bosses or {})[trimmed(p.boss_preset) or trimmed(p.boss_type)] or {}
                sys("boss_defeated_",BossIdentity.placed(p,o.instance_id))
                if cutscene_optional(p.defeat_cutscene) then sys("cutscene_seen_boss_",BossIdentity.placed(p,o.instance_id)) end
                local flag=M.effective_boss_flag(p,preset)
                loc.property=trimmed(p.reward_unlock_flag) and "reward_unlock_flag" or trimmed(p.defeat_flag) and "defeat_flag" or "on_defeat.unlock_flag"
                -- Authored literal none was already reported by the field row;
                -- a selected preset value still needs its own config finding.
                if flag~="none" or p[loc.property]~="none" then add(flag,"writer",loc) end
                local reward=preset.on_defeat or {}
                sys("fast_travel_",trimmed(p.reward_unlock_fast_travel) or reward.unlock_fast_travel)
            elseif o.type=="fast_travel" then
                sys("fast_travel_",trimmed(p.station_id) or o.instance_id)
            elseif o.type=="save_point" and p.is_fast_travel==true then
                sys("fast_travel_",o.persistent_id or trimmed(p.save_id) or trimmed(o.name) or o.instance_id)
            elseif o.type=="locked_door" or o.type=="timed_door" then
                local key=p.door_id or o.name or ((o.type=="locked_door" and "locked_door_" or "door_")..o.room.."_"..o.object_id)
                add(id(key) or o.instance_id,"both",loc,true)
            elseif o.type=="gate" then
                local key=id(p.gate_id) or o.instance_id
                for _,prefix in ipairs({"gate_","gate_seq_","gate_timer_"}) do sys(prefix,key) end
                sys("gate_group_",trimmed(p.group_id))
            elseif o.type=="secret" then
                sys("secret_",id(p.secret_id) or "secret_"..o.room.."_"..o.object_id)
            elseif o.type=="lore_item" then
                local key=p.lore_id or o.name or "lore_"..o.room.."_"..o.object_id
                for _,prefix in ipairs({"collected_lore_","lore_title_","lore_text_","lore_category_"}) do sys(prefix,key) end
            elseif o.type=="map_station" then
                sys("map_station_used_",id(p.station_id) or o.instance_id)
                local map=o.map or {}; local mp=Properties.flatten(map.properties or {})
                local area=id(p.reveal_area)
                if not area or area:lower()=="current" then area=id(mp.biome) end
                sys("map_revealed_",area)
            elseif o.type=="collectible" or o.type=="key" or o.type=="ability" then
                sys("collected_",id(p.collectible_id) or o.instance_id)
                local def=(configs.collectible_types or {})[p.collectible_type] or {}
                local behavior=def.on_collect
                if behavior=="add_to_collection" then
                    local key=id(p.relic_id) or def.relic_id
                    sys("collected_relic_",key); sys("relic_data_",key)
                elseif behavior=="unlock_lore_entry" then
                    local key=id(p.lore_id) or def.lore_id
                    sys("collected_lore_",key); sys("lore_text_",key)
                end
                if behavior=="reveal_map_area" or behavior=="reveal_nearby" or behavior=="reveal_map_fragment" then
                    sys("map_revealed_",trimmed(p.area_id) or def.area_id)
                end
            end
            local once_flag=trimmed(p.once_flag)
            if o.type=="cutscene" then once_flag=cutscene_optional(p.once_flag)
            elseif o.type=="dialogue_trigger" and p.once_flag=="none" then once_flag=nil end
            if (o.type=="dialogue_trigger" or o.type=="cutscene") and p.trigger_once~=false and p.persist_once~=false and not once_flag then
                local kind=o.type=="cutscene" and "cutscene" or "dialogue_trigger"
                local trigger_id=trimmed(p.trigger_id)
                if o.type=="cutscene" then trigger_id=cutscene_optional(p.trigger_id) end
                local key=trigger_id or (o.room:gsub("[^%w_]+","_") ..
                    (o.type=="dialogue_trigger" and "_dialogue_" or "_cutscene_") .. o.object_id)
                sys("mvtk_trigger_once_",fragment(o.room or "global").."_"..fragment(kind).."_"..fragment(key))
            end
        end
    end
    -- World-state tile layers (G8-10): the object walk skips tile layers, so
    -- read each accepted layer's condition from the normalized map. A layer
    -- Prepare & Check rejects stays in the room tilemap and reads nothing.
    local maps,rooms=index.normalized_maps or {},{}
    for room in pairs(maps) do rooms[#rooms+1]=room end
    table.sort(rooms)
    for _,room in ipairs(rooms) do
        for _,layer in ipairs((require("hooks.core.tilemap_split").state_layers(maps[room]))) do
            for _,field in ipairs({"appear_when","remove_when"}) do
                local location={file="developer/assets/tiled/maps/"..tostring(room)..".lua",room=room,layer=layer.name,property=field}
                for _,name in ipairs(PresenceCondition.flags(layer[field] or "") or {}) do add(name,"reader",location) end
            end
        end
    end
    if trimmed((configs.cutscene_settings or {}).opening) then
        add("cutscene_seen_opening","writer",config_location("narrative/cutscene_settings.lua","opening"),true)
    end
    for key in pairs((configs.abilities or {}).abilities or configs.abilities or {}) do add(key,"both",config_location("abilities.lua",key),true) end
    local dialogues=configs.dialogues or {}
    local reached={}
    local function visit(key)
        if reached[key] then return end
        reached[key]=true
        for _,line in ipairs(dialogues[key] or {}) do
            if line.next then visit(line.next) end
            for _,choice in ipairs(line.choices or {}) do if choice["goto"] then visit(choice["goto"]) end end
        end
    end
    for key in pairs(dialogue_roots) do visit(key) end
    for key,lines in pairs(dialogues) do
        for n,line in ipairs(type(lines)=="table" and lines or {}) do
            local loc=config_location((configs.dialogue_origin or {})[key]=="authored" and "narrative/dialogues_authored.lua" or "narrative/dialogues.lua",key.."["..n.."]")
            if type(line.condition)=="table" then add(line.condition.flag,"reader",loc,false,not reached[key]) end
            add(line.set_flag,"writer",loc,false,not reached[key])
            for _,choice in ipairs(line.choices or {}) do add(choice.set_flag,"writer",loc,false,not reached[key]) end
        end
    end
    local cfg=configs.completion or {}
    for _,ending in ipairs(require("mvtk.game.endings").list(cfg)) do
        local prefix=""
        if ending~=cfg then
            for i,e in ipairs(cfg.endings or {}) do if e==ending then prefix="endings."..i.."."; break end end
        end
        local function loc(field) return config_location("game_completion.lua",prefix..field) end
        if ending.condition=="flag" then add(ending.flag,"reader",loc("flag"))
        elseif ending.condition=="boss" and id(ending.boss_id) then add("boss_defeated_"..ending.boss_id,"reader",loc("boss_id")) end
        local r=type(ending.requires)=="table" and ending.requires or {}
        for _,flag in ipairs(type(r.flags)=="table" and r.flags or {}) do
            if type(flag)=="string" then add(flag,"reader",loc("requires.flags")) end
        end
        for _,boss in ipairs(type(r.bosses)=="table" and r.bosses or {}) do
            if type(boss)=="string" then add("boss_defeated_"..boss,"reader",loc("requires.bosses")) end
        end
        add(ending.reward_flag,"writer",loc("reward_flag"))
        grant(ending.reward or "",loc("reward"),{once_key="ending:"..tostring(ending.id)})
    end
    for key,popup in pairs((configs.tutorials or {}).popups or {}) do
        add(popup.trigger_flag,"both",config_location("tutorial_popups.lua","popups."..key..".trigger_flag"))
    end
    for key,entry in pairs(configs.secrets or {}) do
        local room=type(entry)=="table" and id(entry.room_id)
        room=room and room:gsub("^developer/rooms/", ""):gsub("%.lua$", "")
        if id(room) and (entry.hidden_on_map==true or entry.hidden_in_world==true) then
            local flag=id(entry.reveal_flag)
            if not flag and id(entry.wall_id) then
                -- Hash-derived wall flags are excluded from this name ledger.
                -- Do not invent a secret_<entry key> reader for a wall reveal.
                flag=nil
            else flag=flag or "secret_"..key end
            add(flag,"reader",config_location("secret_rooms.lua",key..".reveal_flag"))
        end
    end
    local read_names={}
    for _,entry in ipairs(reads) do
        if not entry.inactive then read_names[entry.name]=true end
        if not writes[entry.name] and not allowed(entry.name,lint.allow) then
            local nearest,best=nil,3
            for name in pairs(writes) do
                local delta=math.abs(#name-#entry.name)<=2 and distance(entry.name,name) or 3
                if delta<best or (delta==best and nearest and name<nearest) then nearest,best=name,delta end
            end
            local fix=nearest and ("Did you mean '"..nearest.."'?") or "Add a writer, correct the flag, or allow a custom-script flag in world_lint.lua."
            issue(entry,"flag_read_never_written",entry.inactive and "info" or lint.errors==true and "error" or "warning",
                "Flag '"..entry.name.."' is read but never written"..(entry.inactive and " (unreferenced dialogue)." or "."),fix)
        end
    end
    for name,entries in pairs(writes) do
        if not read_names[name] then
            for _,entry in ipairs(entries) do
                if not entry.system and not allowed(name,lint.allow) then
                    issue(entry,"flag_written_never_read","info",
                        "Flag '"..name.."' is written but never read.")
                end
            end
        end
    end
    table.sort(ds,function(a,b)
        local function key(d) return table.concat({d.file or "",d.room or "",tostring(d.object_id or ""),d.property or "",d.code,d.message},"\t") end
        return key(a)<key(b)
    end)
    return ds
end
return M
