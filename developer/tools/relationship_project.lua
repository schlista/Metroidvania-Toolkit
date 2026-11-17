-- Project-side relationship gate. Reads disk on every invocation; never trusts
-- package.loaded or the last successful index to approve a changed draft.
local Relationships = require "developer.tools.content_relationships"
local Source = require "developer.tools.project_source"
local DialogueSources = require "mvtk.dialogue.dialogue_sources"
local LootSource = require "mvtk.game.loot_tables_source"
local Adler32 = require "mvtk.core.adler32"
local M = {}
M.index_path = "developer/assets/tiled/content_index.json"
M.report_path = "developer/assets/tiled/relationship_diagnostics.txt"

local read = Source.read
M.read = read

-- Portable checksum for freshness (not a security hash), also implemented in
-- the Tiled extension. Small integer arithmetic works in LuaJIT and JavaScript.
function M.fingerprint(s)
    s=s:gsub("^\239\187\191", ""):gsub("\r\n","\n")
    return Adler32.fingerprint(s)
end

local load_table = Source.load_table

M.load_table = load_table

function M.json(value)
    local t=type(value)
    if t=="nil" then return "null" end
    if t=="boolean" or t=="number" then return tostring(value) end
    if t=="string" then
        return '"' .. value:gsub('[%z\1-\31\\"]',function(c)
            if c=='"' then return '\\"' end
            if c=='\\' then return '\\\\' end
            return string.format('\\u%04x',c:byte())
        end) .. '"'
    end
    assert(t=="table","Cannot serialize relationship index value: " .. t)
    local parts={}
    if #value>0 or (getmetatable(value) or {}).__json_array then
        for _,v in ipairs(value) do parts[#parts+1]=M.json(v) end
        return '[' .. table.concat(parts,',') .. ']'
    end
    local keys={}; for k in pairs(value) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do parts[#parts+1]=M.json(tostring(k)) .. ':' .. M.json(value[k]) end
    return '{' .. table.concat(parts,',') .. '}'
end

function M.check(opts)
    opts=opts or {}
    local root=opts.root or "."
    local get=opts.read or read
    local maps, diagnostics, sources = {},{},{}
    local fresh_root=tostring(root):gsub("\\","/"):gsub("/$","")
    local config_sources={}
    local fresh=require("mvtk.editor.fresh_config").new({root=root,read=function(path)
        local text=get(path)
        if text then
            local relative=path:sub(#fresh_root+2)
            config_sources[relative]=M.fingerprint(text)
        end
        return text
    end})
    local source_complete=true
    local function issue(code,path,message)
        diagnostics[#diagnostics+1]={severity="error",code=code,file=path,
            message=message,fix="Correct the file, export the room from Tiled, then run Prepare & Check."}
    end
    local function read_table(path)
        local value,err
        if path:match("^developer/config/") then
            value,err=fresh.load_path(path)
            sources[path]=config_sources[path]
        else
            local text=get(root .. "/" .. path)
            if text then sources[path]=M.fingerprint(text) end
            value,err=load_table(text,path)
        end
        if not value then issue("content_source_unavailable",path,tostring(err)) end
        return value
    end
    local dir="developer/assets/tiled/maps"
    local files=opts.files
    if not files then
        if opts.list_dir_filesystem then
            local ok,_,result=pcall(opts.list_dir_filesystem,root .. "/" .. dir)
            if ok then files=result end
        elseif editor then
            local _,result=require("hooks.core.filesystem").list_dir_filesystem(root .. "/" .. dir)
            files=result
        else
            files=require("developer.tools.dev_helpers").list_files(root .. "/" .. dir)
        end
    end
    if type(files)~="table" then issue("content_index_unavailable",dir,"Cannot enumerate Tiled room exports."); files={} end
    for _,name in ipairs(files) do
        name=name:gsub("\\","/"):match("([^/]+)$")
        if name:match("%.lua$") and name:sub(1,1)~="." then
            local room=name:gsub("%.lua$","")
            local path=dir .. "/" .. name
            local map=read_table(path)
            if map then
                maps[room]={file=path,map=map}
                local tmx_path=dir .. "/" .. room .. ".tmx"
                local tmx=get(root .. "/" .. tmx_path)
                if tmx then
                    sources[tmx_path]=M.fingerprint(tmx)
                    if not map.mvtk_source_signature then
                        source_complete=false
                        diagnostics[#diagnostics+1]={severity="warning",code="export_freshness_unverified",
                            file=tmx_path,room=room,message="This legacy Lua export has no source fingerprint; TMX freshness is unverified.",
                            fix="Export this map once with Export Lua + Defold Tilemap, then run Prepare & Check."}
                    elseif map.mvtk_source_signature~=sources[tmx_path] then
                        issue("stale_tiled_export",tmx_path,"The saved Tiled map changed after its last Lua export.")
                    end
                elseif map.mvtk_source_signature then
                    issue("stale_tiled_export",tmx_path,"The source map for this export is missing.")
                end
            end
        end
    end
    local abilities=read_table("developer/config/abilities.lua")
    local dialogues=read_table("developer/config/narrative/dialogues.lua")
    local authored=get(root .. "/developer/config/narrative/dialogues_authored.lua") and read_table("developer/config/narrative/dialogues_authored.lua")
    local dialogue_origin
    dialogues,dialogue_origin=DialogueSources.merge(dialogues,authored)
    local cutscenes=get(root .. "/developer/config/narrative/cutscenes.lua") and read_table("developer/config/narrative/cutscenes.lua")
    local cutscene_settings=get(root .. "/developer/config/narrative/cutscene_settings.lua") and read_table("developer/config/narrative/cutscene_settings.lua")
    local default_bindings=get(root .. "/developer/config/default_bindings.lua") and read_table("developer/config/default_bindings.lua")
    local videos=get(root .. "/developer/config/narrative/videos.lua") and read_table("developer/config/narrative/videos.lua")
    local quest_refs=get(root .. "/developer/config/quests.lua") and read_table("developer/config/quests.lua")
    local arenas=read_table("developer/config/boss_arenas.lua")
    local bosses=read_table("developer/config/boss_types.lua")
    local ok,index=pcall(Relationships.build_index,maps)
    -- Persist per-room scrolling-art warnings in the existing authoring report.
    -- The reader is also used by the hull baker (including external TSX shapes).
    local collision_rooms={}
    for id in pairs(maps) do collision_rooms[#collision_rooms+1]=id end
    table.sort(collision_rooms)
    for _, room in ipairs(collision_rooms) do
        local record=maps[room]
        local Collision=require "hooks.core.room_collision"
        -- Static rooms need no TSX reads for this warning-only check.
        if next(Collision.scrolling_layer_names(record.map)) then
            local _, warnings=Collision.scan(record.map,root .. "/" .. record.file,room,
                require("hooks.core.tilesource").get_tileset_meta)
            for _, d in ipairs(warnings) do
                if d.code=="scrolling_layer_collision" then diagnostics[#diagnostics+1]=d end
            end
        end
    end
    if not ok then
        issue("invalid_content_index",dir,tostring(index))
        index={objects={},rooms={},definitions={},references={}}
    else
        local ds=Relationships.validate(index,{ability_config=abilities,dialogue_config=dialogues,
            quest_config=quest_refs,arena_config=arenas,boss_config=bosses,cutscene_config=cutscenes,video_config=videos,published_rooms=opts.published_rooms})
        for _,d in ipairs(ds) do diagnostics[#diagnostics+1]=d end
    end
    if opts.published_rooms then
        for room in pairs(opts.published_rooms) do
            if not maps[room] then issue("missing_layout_room",dir .. "/" .. room .. ".lua","Published layout references a missing room.") end
        end
    end
    local completion=require "developer.tools.completion_authoring"
    local loaded,ending,ending_err=pcall(completion.load,root,get,fresh.load_path)
    -- Keep the serialized input inventory stable: optional generated configs
    -- can change later in Create Rooms, after this preflight publishes its index.
    for _,path in ipairs({"developer/config/game_completion.lua","developer/config/creator_settings.lua"}) do
        sources[path]=config_sources[path]
    end
    loaded=loaded and ending~=nil
    if not loaded then issue("invalid_completion_config","developer/config/game_completion.lua",tostring(ending_err or ending))
    end
    -- Content checks for mistakes that otherwise fail silently in play.
    -- Missing optional config files skip their check instead of erroring.
    -- Generation preflights check authored inputs only: Create Rooms produces
    -- the chest lookup. Validation/build/publication check it by default,
    -- including when the generated file is missing after a reset.
    local function optional_table(path)
        local value=fresh.load_path(path)
        return type(value)=="table" and value or nil
    end
    local tracking=optional_table("developer/config/completion_tracking.lua")
    local census_rules=optional_table("developer/config/world_census.lua")
    if tracking and census_rules then
        for _,d in ipairs(completion.validate_tracking(tracking,census_rules)) do diagnostics[#diagnostics+1]=d end
    end
    local Checks=require "developer.tools.content_checks"
    local boss_patterns=optional_table("mvtk/bosses/patterns/attack_patterns.lua") or {}
    for name,pattern in pairs(optional_table("developer/config/attack_patterns.lua") or {}) do
        boss_patterns[name]=pattern
    end
    local CatalogEnums=require "mvtk.tiled.catalog_enums"
    local catalogs,map_properties={},{}
    -- Read the carrier through the caller's filesystem even in the game process.
    local carrier=get(root.."/MVTK.tiled-project")
    for _,row in ipairs(CatalogEnums.rows()) do
        if row.kind~="external" then
            local values,err,reason=CatalogEnums.derive(row,function(name)
                return fresh.load_path(name:gsub("%.","/")..".lua")
            end,carrier,nil,{allow_empty=true})
            if values then
                local catalog={values={},sentinels={},source=row.module and row.module:gsub("%.","/")..".lua",
                    severity=row.unknown or "error",flags=row.flags,map_properties=row.map_properties}
                for _,value in ipairs(values) do catalog.values[value]=true end
                for _,value in ipairs(row.sentinels or {}) do catalog.sentinels[value]=true end
                for _,value in ipairs(row.tail or {}) do catalog.sentinels[value]=true end
                catalogs[row.name]=catalog
            elseif reason~="missing" then
                issue("content_source_unavailable",row.module and row.module:gsub("%.","/")..".lua" or "MVTK.tiled-project",tostring(err))
            end
        end
    end
    for room,entry in pairs(maps) do map_properties[room]=entry.map.properties or {} end
    -- Resolve ambience conflicts against the same selected defaults/membership as
    -- runtime. Explicit room "none" silences a world loop; unrelated maps do not inherit.
    local world_properties, world_rooms = {}, {}
    local world = opts.world_manifest
    if not world and opts.layout and opts.layout.source and opts.layout.source.kind == "tiled" then
        world = opts.layout
    end
    if not world then
        world = require("developer.tools.world_manifest").selected_manifest({root = root, read = function(path)
            local text = get(path)
            if text then sources[path:sub(#fresh_root + 2)] = M.fingerprint(text) end
            return text
        end})
    end
    if world then
        world_properties = world.world_properties or {}
        for _, member in ipairs(world.maps or world.rooms or {}) do world_rooms[member.id] = true end
    end
    local creator=optional_table("developer/config/creator_settings.lua")
    if cutscene_settings then cutscene_settings=require("mvtk.core.creator_settings_model").merge(cutscene_settings, ((creator or {}).overrides or {}).cutscenes or {}) end
    local leveling=optional_table("developer/config/leveling.lua") or {}
    if creator and creator.published then leveling=require("mvtk.core.creator_settings_model").merge(leveling, (creator.overrides or {}).leveling or {}) end
    local bestiary=optional_table("developer/config/bestiary.lua") or {}
    if creator and creator.published then bestiary=require("mvtk.core.creator_settings_model").merge(bestiary, (creator.overrides or {}).bestiary or {}) end
    local achievements=optional_table("developer/config/achievements.lua")
    if achievements and creator and creator.published then achievements=require("mvtk.core.creator_settings_model").merge(achievements, (creator.overrides or {}).achievements or {}) end
    local weapons=optional_table("developer/config/weapons.lua") or {}
    if creator and creator.published then weapons=require("mvtk.core.creator_settings_model").merge(weapons,(creator.overrides or {}).weapons or {}) end
    local weapon_combat=optional_table("developer/config/combat_config.lua") or {}
    for _,entry in ipairs(weapons.weapons or {}) do
        if type(entry)=="table" and not (weapon_combat.attack_sets or {})[entry.attack_set or "default"] then
            issue("invalid_weapon_attack_set","developer/config/weapons.lua",
                "Weapon "..tostring(entry.id).." attack_set must name a current combat_config.lua attack set.")
        end
    end
    local charms=optional_table("developer/config/charms.lua") or {}
    if creator and creator.published then charms=require("mvtk.core.creator_settings_model").merge(charms,(creator.overrides or {}).charms or {}) end
    local random_drops=optional_table("developer/config/random_drops.lua") or {}
    if creator and creator.published then random_drops=require("mvtk.core.creator_settings_model").merge(random_drops,(creator.overrides or {}).random_drops or {}) end
    local map_icons=optional_table("developer/config/map_icons.lua")
    if map_icons and creator and creator.published then map_icons=require("mvtk.core.creator_settings_model").merge(map_icons,(creator.overrides or {}).map_icons or {}) end
    local powerups=optional_table("developer/config/powerups.lua") or {}
    if creator and creator.published then powerups=require("mvtk.core.creator_settings_model").merge(powerups,(creator.overrides or {}).powerups or {}) end
    local quests=optional_table("developer/config/quests.lua")
    if quests and creator and creator.published then quests=require("mvtk.core.creator_settings_model").merge(quests,(creator.overrides or {}).quests or {}) end
    local goals=optional_table("developer/config/goals.lua")
    local countdowns=optional_table("developer/config/countdowns.lua")
    if countdowns and creator and creator.published then countdowns=require("mvtk.core.creator_settings_model").merge(countdowns,(creator.overrides or {}).countdowns or {}) end
    if goals and creator and creator.published then goals=require("mvtk.core.creator_settings_model").merge(goals,(creator.overrides or {}).goals or {}) end
    local shops=optional_table("developer/config/shops.lua")
    local upgrades=optional_table("developer/config/upgrades.lua")
    local grant_env=require("mvtk.game.grant_spec").authoring_env({
        -- Preflight must permit rebuilding stale generated ids. The validation
        -- stage after generation reads the new census and checks grants fully.
        world_census=optional_table("developer/config/world_census_generated.lua") or {rooms={}},
        skip_travel_validation=opts.check_generated == false,
        items=optional_table("developer/config/items.lua"),
        upgrades=upgrades, weapons=weapons, charms=charms,
        collectible_types=optional_table("developer/config/collectible_types.lua"), abilities=abilities,
        key_ids=require "mvtk.core.key_ids", hud_layout=optional_table("developer/config/hud_layout.lua"),
        creator_settings=creator, reward_text=optional_table("developer/config/reward_text.lua"),
        leveling=leveling,
        currency_format=require "mvtk.core.currency_format"})
    if tracking and creator and creator.published then
        tracking=require("mvtk.core.creator_settings_model").merge(tracking,(creator.overrides or {}).completion_tracking or {})
    end
    if loaded then
        for _,d in ipairs(completion.validate(ending,index,bosses,opts.layout,tracking or {},grant_env)) do diagnostics[#diagnostics+1]=d end
    end
    local crafting=optional_table("developer/config/crafting.lua")
    if crafting and creator and creator.published then crafting=require("mvtk.core.creator_settings_model").merge(crafting,(creator.overrides or {}).crafting or {}) end
    if crafting then
        for _,err in ipairs(require("mvtk.game.grant_spec").validate_crafting(crafting,grant_env)) do
            issue("invalid_crafting","developer/config/crafting.lua",err)
        end
    end
    if achievements then
        for _,err in ipairs(require("mvtk.game.progression.achievement_rules").validate(achievements,require("mvtk.core.game_events").EVENTS,grant_env,tracking,loaded and ending or {enabled=false})) do
            issue("invalid_achievement","developer/config/achievements.lua",err)
        end
    end
    if quests then
        for _,err in ipairs(require("mvtk.game.quests.quest_rules").validate(quests,grant_env)) do
            issue("invalid_quest","developer/config/quests.lua",err)
        end
    end
    if goals then
        for _,err in ipairs(require("mvtk.game.goal_rules").validate(goals,{abilities=abilities and abilities.abilities})) do
            issue("invalid_goal","developer/config/goals.lua",err)
        end
    end
    local effective=Checks.effective_settings({
        game_config=optional_table("developer/config/game_config.lua"),
        fragments=optional_table("developer/config/fragments.lua"),
        healing=optional_table("developer/config/healing.lua"),
        ability_defaults=optional_table("developer/config/ability_defaults.lua"),
        player_settings=optional_table("developer/config/player_settings.lua"),
        creator=creator})
    local chest_inline,extras_gallery,item_art
    if opts.check_generated ~= false then
        chest_inline=optional_table("developer/config/chest_inline_contents.lua") or {}
        item_art=optional_table("developer/config/item_art_generated.lua") or {}
        extras_gallery=optional_table("developer/config/extras_gallery_generated.lua")
    end
    local extras=optional_table("developer/config/extras.lua")
    if extras and creator and creator.published then extras=require("mvtk.core.creator_settings_model").merge(extras,(creator.overrides or {}).extras or {}) end
    local loot_tables,loot_table_origins=LootSource.merge(optional_table("developer/config/loot_tables.lua"), optional_table("developer/config/loot_tables_authored.lua"))
    local pickup_index
    if item_art then
        local pickup_ok,pickup_result=pcall(require("developer.tools.pickup_art_checks").with_tile_defaults,index,function(ts, source)
            return require("hooks.core.tilesource").get_tileset_meta(ts, root .. "/" .. source)
        end)
        if pickup_ok then pickup_index=pickup_result
        else
            pickup_index={objects={}}
            issue("pickup_metadata_unavailable",dir,tostring(pickup_result))
        end
    end
    local checks_ok,check_ds=pcall(Checks.validate,index,{pickup_index=pickup_index,item_art=item_art,object_art=optional_table("developer/config/object_art.lua"),loot_table_origins=loot_table_origins,accessibility=optional_table("developer/config/accessibility.lua"),player=effective.player,abilities=effective.abilities,max_energy=effective.max_energy,
        tile_settings=optional_table("developer/config/tile_settings.lua"),world_lint=optional_table("developer/config/world_lint.lua"),
        random_drops=random_drops,charms=charms,weapons=weapons,powerups=powerups,bestiary=bestiary,world_census=optional_table("developer/config/world_census_generated.lua"),
        shops=shops,upgrades=upgrades,items=grant_env.items,
        npc_types=optional_table("developer/config/npc_types.lua"),
        loot_tables=loot_tables,
        combat_music=optional_table("developer/config/combat_music.lua"),
        music_tracks=optional_table("developer/config/music_tracks_generated.lua"),
        extras=extras,extras_gallery=extras_gallery,countdowns=countdowns,achievements=achievements,game_completion=loaded and ending or nil,
        ambience_tracks=optional_table("developer/config/ambience_tracks.lua"),
        boss_types=bosses,boss_arenas=arenas,boss_attack_patterns=boss_patterns,
        boss_ui=optional_table("developer/config/boss_ui.lua"),
        cutscene_settings=cutscene_settings,cutscenes=cutscenes,default_bindings=default_bindings,dialogues=dialogues,
        videos=videos,languages=(optional_table("developer/config/localization.lua") or {}).languages,
        creator_settings=creator,enemy_types=optional_table("developer/config/enemy_types.lua"),
        enemy_defaults=optional_table("developer/config/enemy_defaults.lua"),
        enemy_skins=optional_table("developer/config/enemy_skins_generated.lua"),published_rooms=opts.published_rooms,
        max_stamina=effective.max_stamina,fragments=effective.fragments,healing=effective.healing,collectible_types=optional_table("developer/config/collectible_types.lua"),
        movement_zone_types=optional_table("developer/config/movement_zone_types.lua"),
        gate_types=optional_table("developer/config/gate_types.lua"),
        map_icons=map_icons,
        player_actions=optional_table("developer/config/player_actions.lua"),
        combat_attacks=(optional_table("developer/config/combat_config.lua") or {}).attacks,
        combat_features=(optional_table("developer/config/combat_config.lua") or {}).features,
        carry_settings=optional_table("developer/config/carry_settings.lua"),
        hazard_types=optional_table("developer/config/hazard_types.lua"),hazard_return_enabled=effective.hazard_return_enabled,
        chest_inline=chest_inline,grant_env=grant_env,catalogs=catalogs,
        usage=require "mvtk.tiled.enum_usage",map_properties=map_properties,
        world_properties=world_properties,world_rooms=world_rooms})
    if not checks_ok then issue("content_checks_failed","developer/tools/content_checks.lua",tostring(check_ds))
    else for _,d in ipairs(check_ds) do diagnostics[#diagnostics+1]=d end end
    local FlagLedger=require "developer.tools.flag_ledger"
    local shop_grants={}
    for catalog_id,catalog in pairs((shops or {}).catalogs or {}) do
        for _,entry in ipairs(catalog.entries or {}) do
            local set_flags={}
            if entry.set_flag and entry.set_flag~="" then set_flags[entry.set_flag]=true end
            shop_grants[#shop_grants+1]={give=entry.gives,set_flags=set_flags,
                location={file="developer/config/shops.lua",property="catalogs."..catalog_id..".entries."..entry.id}}
        end
    end
    for id,row in pairs(type((achievements or {}).achievements)=="table" and achievements.achievements or {}) do
        if type(row)=="table" and row.reward then
            shop_grants[#shop_grants+1]={give=row.reward,once_key="achievement:"..tostring(id),
                location={file="developer/config/achievements.lua",property=tostring(id)..".reward"}}
        end
    end
    for id,row in pairs(type((quests or {}).quests)=="table" and quests.quests or {}) do
        if type(row)=="table" then
            shop_grants[#shop_grants+1]={give=row.rewards or {},once_key="quest:"..tostring(id),
                location={file="developer/config/quests.lua",property="quests."..tostring(id)..".rewards"}}
        end
    end
    for id,row in pairs(type((countdowns or {}).countdowns)=="table" and countdowns.countdowns or {}) do
        if type(row)=="table" and type(row.reward)=="string" and row.reward:find("%S") then
            shop_grants[#shop_grants+1]={give=row.reward,once_key="countdown:"..tostring(id),
                location={file="developer/config/countdowns.lua",property="countdowns."..tostring(id)..".reward"}}
        end
    end
    for _,d in ipairs(FlagLedger.check(index,{abilities=abilities,dialogues=dialogues,dialogue_origin=dialogue_origin,bosses=bosses,shops=shops,grants=shop_grants,achievements=achievements,quests=quests,goals=goals,countdowns=countdowns,crafting=crafting,extras=extras,
        cutscene_settings=cutscene_settings,cutscenes=cutscenes, leveling=leveling,
        completion=loaded and ending or nil, tutorials=optional_table("developer/config/tutorial_popups.lua"),
        map_icons=map_icons,biomes=optional_table("developer/config/biomes.lua"),map_properties=map_properties,
        secrets=optional_table("developer/config/secret_rooms.lua"),npc_types=optional_table("developer/config/npc_types.lua"),
        collectible_types=optional_table("developer/config/collectible_types.lua")},
        optional_table("developer/config/world_lint.lua"))) do diagnostics[#diagnostics+1]=d end
    local summary=Relationships.summary(diagnostics)
    local report={ok=summary.errors==0,index=index,diagnostics=diagnostics,summary=summary,sources=sources,source_complete=source_complete,
        ending=loaded and ending or nil,configs={player=effective.player,abilities=abilities and abilities.abilities,dialogues=dialogues,arenas=arenas,bosses=bosses,cutscenes=cutscenes,videos=videos,cutscene_settings=cutscene_settings,default_bindings=default_bindings}}
    local lines={}
    for _,d in ipairs(diagnostics) do lines[#lines+1]=Relationships.format_diagnostic(d) end
    lines[#lines+1]="Locate in Tiled: open the room TMX, use View > Views and Toolbars > Objects, and find the object ID."
    lines[#lines+1]="Locate in Defold: open developer/rooms/collections/<room>.collection and select <room>_<type>_<object_id>."
    report.message=table.concat(lines,"\n")
    return report
end

function M.snapshot(report)
    local objects=setmetatable({}, {__json_array=true})
    for _,o in ipairs(report.index.objects) do
        objects[#objects+1]={room=o.room,file=o.file,layer=o.layer,object_id=o.object_id,type=o.type,
            name=o.name,visible=o.visible,instance_id=o.instance_id,persistent_id=o.persistent_id,properties=o.properties}
    end
    local configs={}
    for kind,config in pairs(report.configs) do
        configs[kind]={}
        for key in pairs(kind=="arenas" and (config.arenas or config) or config) do configs[kind][key]=true end
    end
    configs.keys={}
    local Keys=require "mvtk.core.key_ids"
    for _,key in ipairs(Keys.canonical_ids()) do configs.keys[key]=true end
    for alias in pairs(Keys.AUTHORED_TO_CANONICAL) do configs.keys[alias]=true end
    configs.boss_phase_counts={}
    for id,config in pairs(report.configs.bosses or {}) do
        if type(config)=="table" and type(config.phases)=="table" then configs.boss_phase_counts[id]=#config.phases end
    end
    return {version=2,sources=report.sources,objects=objects,configs=configs,completion=report.ending,source_complete=report.source_complete}
end

function M.publish_report(report,opts)
    opts=opts or {}; local root=opts.root or "."
    local function put(path,text)
        if (opts.read or M.read)(root .. "/" .. path)==text then return false end
        if opts.write then return opts.write(root .. "/" .. path,text) end
        if package.loaded["hooks.core.io_stats"] then package.loaded["hooks.core.io_stats"].add("raw_writes") end
        local f=assert(io.open(root .. "/" .. path,"wb")); assert(f:write(text)); assert(f:close())
    end
    put(M.report_path,report.message .. "\n")
    -- A failed scan never replaces the last valid cross-room registry.
    if report.ok then put(M.index_path,M.json(M.snapshot(report)) .. "\n") end
end

function M.require_valid(opts)
    local report=M.check(opts)
    if opts and opts.publish_report then M.publish_report(report,opts) end
    if opts and opts.log then
        for _,d in ipairs(report.diagnostics) do opts.log(Relationships.format_diagnostic(d)) end
    end
    if not report.ok then error("Authored relationships block publication:\n" .. report.message,0) end
    return report
end

return M
