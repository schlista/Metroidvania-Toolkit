-- Authoring-only rules for the progression model. These describe existing
-- gameplay; they never create objects, grant runtime rewards or run callbacks.
local Keys = require "mvtk.core.key_ids"
local AbilityTags = require "mvtk.abilities.ability_tags"
local BreakableRules = require "mvtk.world.breakable_rules"
local HazardImmunity = require "mvtk.world.hazard_immunity"
local M = {}

M.barriers = {gate=true,locked_door=true,timed_door=true,breakable_wall=true,hazard=true,pressure_plate=true}

-- AND two ability expressions without losing either one's nested OR. Each
-- pair of alternatives is a conjunction; independent prerequisites distribute.
local function combine(req, added)
    req.abilities = req.abilities or {}
    for ability in pairs(added.abilities or {}) do req.abilities[ability] = true end
    if not added.any then return end
    if not req.any then req.any = added.any; return end
    local alternatives = {}
    for _, left in ipairs(req.any) do for _, right in ipairs(added.any) do
        local branch = {}
        combine(branch, left)
        combine(branch, right)
        alternatives[#alternatives + 1] = branch
    end end
    req.any = alternatives
end

local function require_ability(ability, req, ctx, property, visiting)
    if not ability then return end
    if ctx.config.abilities and not ctx.config.abilities[ability] then
        local message="Undefined ability requirement: " .. ability
        ctx.diag("warning","undefined_ability_requirement",ctx.object.room,message,ctx.object,property)
        return message
    end
    req.abilities[ability]=true
    local definition = (ctx.config.abilities or {})[ability] or {}
    local prerequisites = definition.prerequisites
    if not prerequisites then return end
    visiting = visiting or {}
    if visiting[ability] then
        local message = "Cyclic ability prerequisite: " .. ability
        ctx.diag("warning", "cyclic_ability_prerequisite", ctx.object.room, message, ctx.object, property)
        return message
    end
    visiting[ability] = true
    local unknown
    if prerequisites.any then
        local alternatives = {}
        for _, id in ipairs(prerequisites.any) do
            local branch = {abilities = {}}
            local err = require_ability(id, branch, ctx, property, visiting)
            unknown = unknown or err
            alternatives[#alternatives + 1] = branch
        end
        combine(req, {any = alternatives})
    end
    visiting[ability] = nil
    return unknown
end
M.require_ability = require_ability

-- Reverse the wall's forward tag set, just as real hit acceptance does.
-- Several emitters are alternative ways to satisfy the same hit requirement.
function M.wall_emitters(required, config)
    local found,core={},false
    for tag in pairs(AbilityTags.tags_for(required,config.player_actions,config.combat_attacks,config.abilities)) do
        if AbilityTags.CORE_TAGS[tag] then core=true end
        for _,ability in ipairs(AbilityTags.abilities_for_tag(tag,config.player_actions,config.combat_attacks,config.abilities)) do
            found[ability]=true
        end
    end
    local ids={}; for ability in pairs(found) do ids[#ids+1]=ability end
    table.sort(ids)
    return ids,core
end

local function emitter_requirement(ids, core, ctx, code, property, value)
    if core then return end
    if #ids==1 then return require_ability(ids[1],ctx.requirements,ctx,property) end
    if #ids>1 then
        local alternatives,unknown={},nil
        for _,ability in ipairs(ids) do
            local branch={abilities={}}
            local err=require_ability(ability,branch,ctx,property)
            unknown=unknown or err
            alternatives[#alternatives+1]=branch
        end
        combine(ctx.requirements,{any=alternatives})
        return unknown
    end
    local message="No ability emits a hit for " .. value .. "."
    ctx.diag("warning",code,ctx.object.room,message,ctx.object,property)
    return message
end

-- Keep every ability-style gate in lockstep with the runtime manager. Blank
-- singular properties retain the preset's existing default, as before.
local function ability_requirement(p, defaults, req, cost, ctx)
    local ids={}
    local singular=ctx.id(p.required_ability) or ctx.id(defaults.required_ability)
    if singular then ids[singular]="required_ability" end
    local list=p.required_abilities or defaults.required_abilities or ""
    if type(list)=="string" and list~="" then list=require("mvtk.world.switch_state").parse_order(list) end
    if type(list)=="table" then for _,ability in ipairs(list) do
        ids[ability]=ids[ability] or "required_abilities"
    end end
    local ordered={}; for ability in pairs(ids) do ordered[#ordered+1]=ability end; table.sort(ordered)
    local unknown,alternatives=nil,{}
    local any=(p.requirement_logic or defaults.requirement_logic)=="any" and #ordered>0
    for _,ability in ipairs(ordered) do
        local branch={abilities={}}
        local err=require_ability(ability,branch,ctx,ids[ability])
        unknown=unknown or err
        if any then alternatives[#alternatives+1]=branch else combine(req,branch) end
    end
    if any then
        -- An undefined alternative cannot prove a blocked route. The edge's
        -- unknown reason still prevents a definite reachable verdict.
        if unknown then alternatives[#alternatives+1]={} end
        combine(req,{any=alternatives})
    end
    return unknown
end

M.gate_kinds = {
    intangible_barrier=function(p, defaults, req, cost, ctx)
        local config=(ctx.config.player or {}).intangible_dash or {}
        local unknown=require_ability("intangible_dash",req,ctx,"gate_type")
        if config.during_air_dash == false then
            if config.during_slide == true then
                unknown=unknown or require_ability("slide",req,ctx,"gate_type")
            else
                req.any={} -- Neither configured movement mode can cross this barrier.
            end
        elseif config.during_slide == true then
            req.any={{abilities={air_dash=true}}, {abilities={slide=true}}}
        else
            unknown=unknown or require_ability("air_dash",req,ctx,"gate_type")
        end
        return unknown
    end,
    staged=function(p, defaults, req, cost, ctx)
        local flags=p.stage_flags or defaults.stage_flags or {}
        if type(flags)~="table" then flags=require("mvtk.world.switch_state").parse_order(flags) end
        local need=tonumber(p.stages_required)
        if not need or need<0 then need=tonumber(defaults.stages_required) or 0 end
        req.counts={{need=need,flags=flags}}
        -- Resolved after the object loop, when all reward producers are known.
        ctx.stage_flags=flags
    end,
    sequence=function() return "switch-order gate: playtest" end,
    switch=function(p, defaults, req, cost, ctx)
        return "switch-opened gate (channel " .. (ctx.id(p.gate_id) or ctx.object.instance_id) .. "): playtest"
    end,
    ability_requirement=ability_requirement,
    item_requirement=function(p, defaults, req, cost, ctx)
        local item=ctx.id(p.required_item) or ctx.id(p.required_key) or ctx.id(defaults.required_item)
        if item then
            req.items[Keys.canonicalize(item)]=1
            if defaults.consume_item then cost[Keys.canonicalize(item)]=1 end
        end
    end,
    action_barrier=function(p, defaults, req, cost, ctx)
        local tag=ctx.id(p.required_action) or ctx.id(defaults.required_action)
        local ids=AbilityTags.abilities_for_tag(tag,ctx.config.player_actions,ctx.config.combat_attacks,ctx.config.abilities)
        return emitter_requirement(ids,AbilityTags.CORE_TAGS[tag],ctx,"action_barrier_tag_never_emitted","required_action",tag or "(empty tag)")
    end,
}

M.gate_kinds.height_barrier=M.gate_kinds.ability_requirement
M.gate_kinds.hazard_barrier=M.gate_kinds.ability_requirement
M.gate_kinds.destructible=M.gate_kinds.ability_requirement

-- Element-only walls share runtime family matching. Base attack categories
-- need no unlock; configured infusions offer alternative ability requirements.
function M.wall_damage_emitters(required, config)
    local cfg = config.damage_types or {}
    local types, ids, seen = cfg.types or {}, {}, {}
    local function matches(dtype)
        return dtype and BreakableRules.damage_type_ok(required, dtype, types)
    end
    local base = cfg.player_attacks or {melee="slash", ranged="projectile", movement="impact"}
    for _, dtype in pairs(base) do if matches(dtype) then return {}, true end end
    for _, infusion in ipairs(cfg.player_attack_infusions or {}) do
        if (matches(infusion.melee) or matches(infusion.ranged)) and not seen[infusion.ability] then
            seen[infusion.ability] = true
            ids[#ids + 1] = infusion.ability
        end
    end
    return ids, false
end

M.barrier_kinds = {
    breakable_wall=function(o, ctx)
        local required=BreakableRules.required_ability(ctx.id(o.properties.required_ability),o.properties.wall_type)
        local unknown
        if required then
            local ids,core=M.wall_emitters(required,ctx.config)
            unknown=emitter_requirement(ids,core,ctx,"breakable_wall_requirement_never_emitted","required_ability",required)
        end
        local dtype=ctx.id(o.properties.required_damage_type)
        if dtype then
            local ids,core=M.wall_damage_emitters(dtype,ctx.config)
            local err=emitter_requirement(ids,core,ctx,"breakable_wall_damage_type_never_emitted","required_damage_type",dtype)
            unknown=unknown or err
        end
        return unknown
    end,
    hazard=function(o, ctx)
        local p = o.properties
        -- Rising/switch levels keep their independent runtime and barrier rules.
        if (not p.level_mode or p.level_mode == "" or p.level_mode == "none")
            and (ctx.id(p.arena_id) or ctx.id(p.boss_id)) then return end
        local ability=ctx.id(HazardImmunity.resolve(ctx.id(o.properties.required_resistance),
            (ctx.config.hazard_types or {})[o.properties.hazard_type]))
        if not ability then return "Hazard without ability protection requires playtesting." end
        return require_ability(ability,ctx.requirements,ctx,"required_resistance")
    end,
}

M.edges = {
    zip_line=function(o, ctx)
        local p=o.properties
        local from,to=ctx.id(p.progression_from),ctx.id(p.progression_to)
        if not from or not to then return end
        local a,b=ctx.area(o.room,from),ctx.area(o.room,to)
        local unknown=not o.top_level and "Gameplay objects in Tiled groups are not baked as runtime gameplay." or nil
        ctx.edge({id=o.instance_id,from=a,to=b,requirements=ctx.requirements,
            unknown=unknown,room=o.room,object_id=o.object_id})
        if p.progression_one_way==false then
            ctx.edge({id=o.instance_id..":reverse",from=b,to=a,requirements=ctx.requirements,
                unknown=unknown,room=o.room,object_id=o.object_id})
        end
    end,
    fast_travel=function(o, ctx)
        for _,target in ipairs(ctx.stations) do if target~=o then
            local dest,u=ctx.location(target)
            local p=target.properties
            local tid=(target.relationship_ids or {}).fast_travel_station
                or ctx.id(p.station_id) or target.persistent_id or target.instance_id
            local unknown=ctx.uncertain or u
            if (tonumber(o.properties.unlock_cost) or 0)>0 or (tonumber(p.unlock_cost) or 0)>0 then
                unknown="Station activation currency economy requires playtesting."
            end
            -- kind lets world pacing ignore travel the player must first unlock.
            ctx.edge({id=o.instance_id..":travel:"..target.instance_id,kind="fast_travel",from=ctx.at,to=dest,
                requirements={flags={["fast_travel_"..tid]=true}},unknown=unknown,room=o.room,object_id=o.object_id})
        end end
    end,
    teleporter=function(o, ctx)
        local p=o.properties
        if p.one_way==true then return end
        local target=ctx.teleporters[ctx.id(p.target_id)]
        local pair=ctx.pairs_by_id[ctx.id(p.pair_id)] or {}
        if not target and #pair==2 then target=pair[1]==o and pair[2] or pair[1] end
        if target then
            local dest,u=ctx.location(target)
            local flag=ctx.id(p.requires_flag)
            if flag then ctx.requirements.flags[flag]=true end
            ctx.edge({id=o.instance_id,from=ctx.at,to=dest,requirements=ctx.requirements,
                unknown=ctx.uncertain or u,room=o.room,object_id=o.object_id})
        end
    end,
}

local function key_reward(o, ctx, reward, collectible)
    local p=o.properties
    local amount=tonumber(p.amount)
    if not amount or amount==0 then amount=collectible.value or 1 end
    if amount<1 or amount~=math.floor(amount) then
        ctx.diag("error","invalid_reward_count",o.room,"Key amount must be a positive integer.",o)
    else reward.items[Keys.canonicalize(ctx.id(p.item_id) or ctx.id(p.key_id) or collectible.item_id or "normal")]=amount end
    if p.respawns==true or (p.respawns==nil and collectible.respawns) then
        reward.unknown="Repeatable pickup economy requires playtesting."
        ctx.graph.unmodeled_rewards=true
    end
end

local function station_reward(o,ctx,reward)
    local p=o.properties
    if o.type=="save_point" and p.is_fast_travel~=true then return false end
    local tid=(o.relationship_ids or {}).fast_travel_station
        or ctx.id(p.station_id) or o.persistent_id or o.instance_id
    reward.flags["fast_travel_"..tid]=true
    if (tonumber(p.unlock_cost) or 0)>0 then reward.unknown="Station activation currency economy requires playtesting." end
    return true
end

-- Every catalog grant is a possible reward, never proof of affordability,
-- access flags, stock, prerequisites or mutually exclusive purchases.
local function catalog_reward(o, ctx, reward)
    local p = o.properties
    local catalog_id = ctx.id(p.shop_id) or ctx.id(p.upgrade_catalog)
        or ctx.id(p.trainer_catalog) or ctx.id(p.vendor_shop)
    if not catalog_id then return false end
    local catalog = ((ctx.config.shops or {}).catalogs or {})[catalog_id] or {}
    for _, offer in ipairs(catalog.entries or {}) do
        for _, give in ipairs(require("mvtk.game.grant_spec").parse(offer.gives)) do
            if give.kind == "ability" then reward.abilities[give.id] = true
            elseif give.kind == "item" then
                local key = Keys.canonicalize(give.id)
                reward.items[key] = (reward.items[key] or 0) + give.count
            elseif give.kind == "flag" then reward.flags[give.id] = true
            elseif give.kind == "fast_travel" then reward.flags["fast_travel_" .. give.id] = true end
        end
        local flag = ctx.id(offer.set_flag)
        if flag then reward.flags[flag] = true end
    end
    reward.unknown = "Bought with currency; affordability is not modelled."
    local flag = ctx.id(p.vendor_flag)
    if flag then reward.unknown = reward.unknown .. " Vendor requires flag: " .. flag .. "." end
    ctx.graph.unmodeled_rewards = true
    return true
end

M.rewards = {
    quest_trigger = function(o, ctx, reward)
        local flag = ctx.id(o.properties.set_flag)
        if flag then reward.flags[flag] = true end
        local id = ctx.id(o.properties.quest_id)
        if id and o.properties.action == "complete" then reward.flags["quest_completed_" .. id] = true end
        reward.unknown = "Quest objectives and rewards require playtesting."
        ctx.graph.unmodeled_rewards = true
        return true
    end,
    shop = catalog_reward,
    upgrade_station = catalog_reward,
    skill_trainer = catalog_reward,
    offering_altar = function(o, ctx, reward)
        for _, entry in ipairs(require("mvtk.game.grant_spec").parse(o.properties.reward)) do
            if entry.kind == "ability" then reward.abilities[entry.id] = true
            elseif entry.kind == "item" then
                local key = Keys.canonicalize(entry.id)
                reward.items[key] = (reward.items[key] or 0) + entry.count
            elseif entry.kind == "flag" then reward.flags[entry.id] = true
            elseif entry.kind == "fast_travel" then reward.flags["fast_travel_" .. entry.id] = true end
        end
        local flag = ctx.id(o.properties.set_flag)
        if flag then reward.flags[flag] = true end
        reward.unknown = "Offering cost requires playtesting."
        ctx.graph.unmodeled_rewards = true
        return true
    end,
    npc = function(o, ctx, reward)
        if ctx.id(o.properties.vendor_shop) then return catalog_reward(o, ctx, reward) end
        return false
    end,
    combat_trial=function(o, ctx, reward)
        local p = o.properties
        local trial = ctx.id(p.trial_id) or o.instance_id
        reward.flags[ctx.id(p.clear_flag) or ("trial_cleared_" .. trial)] = true
        for _, entry in ipairs(require("mvtk.game.grant_spec").parse(p.trial_reward)) do
            if entry.kind == "ability" then reward.abilities[entry.id] = true
            elseif entry.kind == "item" then
                local key = Keys.canonicalize(entry.id)
                reward.items[key] = (reward.items[key] or 0) + entry.count
            elseif entry.kind == "flag" then reward.flags[entry.id] = true
            elseif entry.kind == "fast_travel" then reward.flags["fast_travel_" .. entry.id] = true end
        end
        reward.unknown = "Clearing this trial requires a combat playtest."
        ctx.graph.unmodeled_rewards = true
        return true
    end,
    encounter=function(o, ctx, reward)
        local p=o.properties
        if p.repeatable~=true then
            reward.flags[ctx.id(p.clear_flag) or ("encounter_cleared_"..(ctx.id(p.encounter_id) or o.instance_id))]=true
        end
        local key=ctx.id(p.reward_collectible)
        if key and key~="none" then
            local collectible=(ctx.config.collectible_types or {})[key] or {}
            local copy={properties={collectible_type=key,amount=p.reward_amount},room=o.room}
            M.rewards.collectible(copy,ctx,reward)
        end
        reward.unknown="Clearing this encounter requires a combat playtest."
        return true
    end,
    enemy=function(o, ctx, reward)
        local Policy=require "mvtk.enemies.enemy_respawn_policy"
        local p=o.properties or {}
        local flag=ctx.id(type(p.defeat_flag)=="string" and p.defeat_flag:match("^%s*(.-)%s*$"))
        if flag then reward.flags[flag]=true end
        if Policy.for_object(p,ctx.config)=="never" then
            reward.flags[Policy.persist_key(flag,o.instance_id)]=true
        end
        if p.champion == true then
            for _, entry in ipairs(require("mvtk.game.grant_spec").parse(p.champion_reward)) do
                if entry.kind == "ability" then reward.abilities[entry.id]=true
                elseif entry.kind == "item" then
                    local key=Keys.canonicalize(entry.id)
                    reward.items[key]=(reward.items[key] or 0)+entry.count
                elseif entry.kind == "flag" then reward.flags[entry.id]=true
                elseif entry.kind == "fast_travel" then reward.flags["fast_travel_"..entry.id]=true end
            end
            reward.unknown="Defeating this champion requires a combat playtest."
        end
        return true
    end,
    -- WM09: a finish zone may set its countdown's finish flag and pay its
    -- reward once. Beating the clock is never proved, so both stay uncertain.
    countdown_zone=function(o, ctx, reward)
        local p=o.properties or {}
        local id=ctx.id(p.countdown_id)
        if not id or (ctx.id(p.role) or "start")~="finish" then return false end
        local Countdown=require "mvtk.game.countdown_rules"
        local spec=Countdown.entry(ctx.config.countdowns or {},id)
        if not spec then return false end
        reward.flags[spec.finish_flag]=true
        for _, entry in ipairs(require("mvtk.game.grant_spec").parse(spec.reward)) do
            if entry.kind == "ability" then reward.abilities[entry.id]=true
            elseif entry.kind == "item" then
                local key=Keys.canonicalize(entry.id)
                reward.items[key]=(reward.items[key] or 0)+entry.count
            elseif entry.kind == "flag" then reward.flags[entry.id]=true
            elseif entry.kind == "fast_travel" then reward.flags["fast_travel_"..entry.id]=true end
        end
        reward.unknown="Finishing this countdown in time requires a playtest."
        ctx.graph.unmodeled_rewards=true
        return true
    end,
    fast_travel=station_reward,
    save_point=station_reward,
    ability=function(o, ctx, reward)
        if ctx.id(o.properties.ability_id) then reward.abilities[o.properties.ability_id]=true end
        return true
    end,
    key=function(o, ctx, reward)
        key_reward(o,ctx,reward,(ctx.config.collectible_types or {})[o.properties.collectible_type] or {})
        return true
    end,
    collectible=function(o, ctx, reward)
        local p=o.properties
        local collectible=(ctx.config.collectible_types or {})[p.collectible_type] or {}
        if collectible.on_collect=="unlock_ability" and ctx.id(collectible.ability_id) then
            reward.abilities[collectible.ability_id]=true
        elseif p.collectible_type=="key" or collectible.on_collect=="add_to_inventory" or collectible.on_collect=="grant_unique_item" then
            key_reward(o,ctx,reward,collectible)
        else return false end
        return true
    end,
    boss=function(o, ctx, reward)
        local p=o.properties
        local preset=ctx.id(p.boss_preset) or ctx.id(p.boss_type)
        local identity=require("mvtk.bosses.boss_identity").placed(p,o.instance_id)
        if identity then reward.flags["boss_defeated_" .. identity]=true end
        local boss=(ctx.config.boss_types or {})[preset] or {}
        local travel=ctx.id(p.reward_unlock_fast_travel) or ctx.id((boss.on_defeat or {}).unlock_fast_travel)
        if travel then reward.flags["fast_travel_"..travel]=true end
        if preset then
            local boss=(ctx.config.boss_types or {})[preset] or {}
            local flag=require("developer.tools.flag_ledger").effective_boss_flag(p,boss)
            if flag then reward.flags[flag]=true end
            reward.unknown="Defeating this boss requires a combat playtest."
        end
        return true
    end,
}

M.edges.save_point=function(o,ctx)
    if o.properties.is_fast_travel==true then M.edges.fast_travel(o,ctx) end
end

local reward_unknown="Combat, loot or dialogue rewards require playtesting or a preview-state flag/item."
M.unmodeled = {countdown_zone="Countdown runs and their rewards require a timed playtest.",combat_trial="Clearing this trial requires a combat playtest.",quest_trigger="Quest objectives and rewards require playtesting.",encounter="Clearing this encounter requires a combat playtest.",boss=reward_unknown,chest=reward_unknown,npc=reward_unknown,dialogue_trigger=reward_unknown}

-- A drawn vehicle route connects authored areas just like a zip line. Plain
-- moving platforms retain their existing progression behavior.
function M.edges.platform(o, ctx)
    local control = o.properties.vehicle_control
    if control and control ~= "" and control ~= "none" then M.edges.zip_line(o, ctx) end
end
M.edges.moving_platform = M.edges.platform

return M
