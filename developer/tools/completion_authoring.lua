local Source=require "developer.tools.project_source"
local Model=require "mvtk.core.creator_settings_model"
local Endings=require "mvtk.game.endings"
local M={}
function M.load(root,read,load_path)
    read=read or Source.read
    local cfg,creator
    if load_path then
        local err
        cfg,err=load_path("developer/config/game_completion.lua")
        if not cfg and err and not tostring(err):match("^Missing ") then return nil,err end
        creator=load_path("developer/config/creator_settings.lua")
    else
        local text=read(root.."/developer/config/game_completion.lua")
        cfg=text and assert(Source.load_table(text,"game_completion.lua"))
        creator=Source.load_table(read(root.."/developer/config/creator_settings.lua"),"creator_settings.lua")
    end
    cfg=cfg or {enabled=false,id="ending"}
    if creator and creator.published then cfg=Endings.effective(cfg,(creator.overrides or {}).game_completion) end
    return cfg
end
function M.validate(cfg,index,bosses,layout,tracking,grant_env)
    local ds,regions,placed_regions={},{},{}
    local placed={}; for _,room in ipairs(layout and layout.rooms or {}) do placed[room.id]=true end
    local function issue(code,message,o,property,severity,fix)
        ds[#ds+1]={severity=severity or "error",code=code,message=message,file=o and o.file or "developer/config/game_completion.lua",
            room=o and o.room,layer=o and o.layer,object_id=o and o.object_id,property=property or "game_completion",fix=fix}
    end
    local unknown_region=false
    for _,o in ipairs(index.objects or {}) do if o.visible and o.type=="end_game" then
        local ending=Endings.find(cfg,o.properties.completion_id)
        -- Disabled projects still compare the authored main id before re-import.
        if not cfg.enabled and o.properties.completion_id==cfg.id then ending=cfg end
        if not ending or (ending~=cfg and ending.condition~="region") then
            unknown_region=true
            local message="Region completion ID '"..tostring(o.properties.completion_id).."' must match a configured region ending ID (main ending '"..tostring(cfg.id).."')."
            if not cfg.enabled then message=message.." Ending is disabled; use Project > Game Settings... > Ending to match the ID before enabling completion." end
            issue("unknown_completion_id",message,o,"completion_id",cfg.enabled and "error" or "warning",
                "Match a region ending ID or correct this region's completion_id and export again.")
        else
            regions[ending.id]=(regions[ending.id] or 0)+1
            if placed[o.room] then placed_regions[ending.id]=true end
        end
        if not cfg.enabled then issue("ending_disabled","This region is inactive until completion is enabled in Project > Game Settings... > Ending.",o,nil,"warning") end
    end end
    if not cfg.enabled then return ds end
    for _,err in ipairs(Endings.schema_errors(cfg)) do issue("invalid_ending_config",err) end
    local function known_boss(id)
        local found=bosses and bosses[id]
        for _,o in ipairs(index.objects or {}) do
            if o.type=="boss" and (o.properties.boss_id==id or o.properties.boss_preset==id or o.properties.boss_type==id) then found=true end
        end
        return type(id)=="string" and id~="" and found
    end
    for _,ending in ipairs(Endings.list(cfg)) do
        local prefix="Ending '"..tostring(ending.id).."': "
        local function report(code,msg,severity) issue(code,prefix..msg,nil,nil,severity) end
        if type(ending.id)~="string" or not ending.id:match("^[%w_%-]+$") then report("invalid_completion_id","ID must be nonempty letters, digits, underscores or hyphens.") end
        if ending.condition=="region" then
            -- Report the bad region id first, without a cascading missing-region error.
            if not regions[ending.id] and not unknown_region then report("missing_ending_region","Place an end_game template on a top-level templates layer.") end
            if next(placed) and regions[ending.id] and not placed_regions[ending.id] then report("unpublished_ending_region","Place a room containing this end_game region in Layout Editor before publishing the world.") end
        elseif ending.condition=="flag" then
            if type(ending.flag)~="string" or ending.flag=="" then report("missing_ending_flag","Flag ending requires a flag name.") end
        elseif ending.condition=="boss" then
            if not known_boss(ending.boss_id) then report("unknown_ending_boss","Boss ending must name an existing boss preset or persistent boss identity.") end
        else report("invalid_ending_condition","Ending condition must be region, flag, or boss.") end
        if ending.continue_policy~="explore" and ending.continue_policy~="completed" then report("invalid_continue_policy","Continue must be explore or completed.") end
        if ending.continue_policy=="explore" and ending.return_room~="" and layout then
            local valid=false
            for _,r in ipairs(layout.rooms or {}) do
                if r.id==ending.return_room and type(ending.return_x)=="number" and type(ending.return_y)=="number" and ending.return_x>=r.x and ending.return_x<=r.x+r.w and ending.return_y>=r.y and ending.return_y<=r.y+r.h then valid=true end
            end
            if not valid then report("invalid_ending_return","Return point must lie inside its published room (world coordinates).") end
        end
        local requires=type(ending.requires)=="table" and ending.requires or {}
        for _,id in ipairs(type(requires.bosses)=="table" and requires.bosses or {}) do
            if not known_boss(id) then report("unknown_ending_requirement_boss","Required boss '"..tostring(id).."' must exist.") end
        end
        if requires.completion_percent~=nil and tracking and tracking.enabled~=true then
            report("ending_completion_tracking_disabled","Completion requirement needs completion tracking enabled.","warning")
        end
        if ending.reward and ending.reward~="" then
            grant_env=grant_env or require("mvtk.game.grant_spec").authoring_env({items=require "developer.config.items",
                abilities=require "developer.config.abilities",upgrades=require "developer.config.upgrades",
                weapons=require "developer.config.weapons",charms=require "developer.config.charms",
                collectible_types=require "developer.config.collectible_types",key_ids=require "mvtk.core.key_ids",
                world_census=require "developer.config.world_census_generated",leveling=require "developer.config.leveling"})
            local env=Model.copy(grant_env); env.once_key="ending:"..tostring(ending.id)
            local _,diags=require("mvtk.game.grant_spec").validate(ending.reward,env)
            for _,d in ipairs(diags) do report("invalid_ending_reward",d.message,d.severity) end
        end
    end
    return ds
end
-- This relationship warning runs on fresh authored configs, not runtime I/O.
function M.validate_tracking(cfg,census)
    local ds={}
    cfg=type(cfg)=="table" and cfg or {}
    census=type(census)=="table" and census or {}
    local categories=type(cfg.categories)=="table" and cfg.categories or {}
    local function includes(set,key)
        set=type(set)=="table" and set or {}
        if set[key]~=nil then return set[key]==true end
        for _,value in ipairs(set) do if value==key then return true end end
        return false
    end
    local ids={}; for id in pairs(categories) do if type(id)=="string" then ids[#ids+1]=id end end; table.sort(ids)
    for _,id in ipairs(ids) do
        local row=categories[id]
        for _,category in ipairs(type(row)=="table" and type(row.collectible_categories)=="table" and row.collectible_categories or {}) do
            if not includes(census.count_categories or {},category) or includes(census.exclude_categories or {},category) then
                ds[#ds+1]={severity="warning",code="completion_category_uncounted",file="developer/config/completion_tracking.lua",
                    property="categories."..id..".collectible_categories",
                    message="Completion category '"..id.."' includes '"..tostring(category).."', which the world census does not count.",
                    fix="Count this collectible category in world_census.lua or remove it from completion_tracking.lua."}
            end
        end
    end
    return ds
end
return M
