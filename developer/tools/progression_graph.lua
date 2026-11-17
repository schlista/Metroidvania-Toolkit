-- Convert the published door layout and normalized Tiled content into a graph.
-- Annotations describe connectivity, never create runtime objects or rewards.
local Keys = require "mvtk.core.key_ids"
local Properties = require "mvtk.tiled.property_flattener"
local Copy = require("developer.tools.progression_search").copy
local Rules = require "developer.tools.progression_rules"
local PresenceCondition = require "mvtk.world.presence_condition"
local M = {}
local function text(v) return tostring(v or ""):match("^%s*(.-)%s*$") end
local function id(v) local s=text(v); return s~="" and s:lower()~="none" and s or nil end
local function words(v)
    if type(v)=="table" then return Copy(v) end
    local out={}; for s in text(v):gmatch("[^,]+") do out[#out+1]=text(s) end; return out
end
local function assignments(v)
    if type(v)=="table" then return Copy(v) end
    local out={}; for _,s in ipairs(words(v)) do local k,val=s:match("^([^=]+)=(.+)$"); if k then out[text(k)]=text(val) end end; return out
end
local barriers=Rules.barriers
-- World-state appear_when (G8-09) as a search requirement, with item ids in
-- their canonical inventory form. Blank text gives nil; text that does not
-- parse gives false (content_checks reports presence_condition_invalid).
local function presence_requirement(value)
    if PresenceCondition.is_blank(value) then return nil end
    local req=PresenceCondition.parse(value)
    if not req then return false end
    local function canonical(r)
        if r.items then
            local items={}
            for item,amount in pairs(r.items) do
                local key=Keys.canonicalize(item)
                items[key]=math.max(items[key] or 0,amount)
            end
            r.items=items
        end
        for _,branch in ipairs(r.any or {}) do canonical(branch) end
    end
    canonical(req)
    return req
end
local PRESENCE_UNKNOWN="World-state condition on this object requires playtesting."
-- A world-state layer (G8-10) is present while appear_when holds and
-- remove_when does not. Returns the requirement for crossing its barrier, or
-- nil and a reason when the conditions are not made of flags alone.
local function flag_only(req)
    if req.abilities or req.items then return false end
    for _,branch in ipairs(req.any or {}) do if not flag_only(branch) then return false end end
    return true
end
local function alternatives(req)
    if req.any and next(req.flags or {})==nil then return req.any end
    return {req}
end
local function state_layer_requirement(layer,when_present)
    local appear,remove=layer.appear_when or "",layer.remove_when or ""
    local NOT_FLAGS="only conditions made of flags are modeled; playtest this barrier."
    if not when_present then
        -- Absent: appear_when fails, or remove_when holds.
        local any={}
        if not PresenceCondition.is_blank(appear) then
            local negated=PresenceCondition.negate_flags(appear)
            if not negated then return nil,NOT_FLAGS end
            for _,branch in ipairs(alternatives(negated)) do any[#any+1]=branch end
        end
        if not PresenceCondition.is_blank(remove) then
            local req=PresenceCondition.parse(remove)
            if not req or not flag_only(req) then return nil,NOT_FLAGS end
            any[#any+1]=req
        end
        if #any==0 then return nil,NOT_FLAGS end
        return #any==1 and any[1] or {any=any}
    end
    -- Present: appear_when holds and remove_when does not.
    local req=PresenceCondition.is_blank(appear) and {} or PresenceCondition.parse(appear)
    if not req or not flag_only(req) then return nil,NOT_FLAGS end
    if not PresenceCondition.is_blank(remove) then
        local negated=PresenceCondition.negate_flags(remove)
        if not negated then return nil,NOT_FLAGS end
        if negated.any then
            if req.any then return nil,"appear_when and remove_when both list alternatives; playtest this barrier." end
            req.any=negated.any
        else
            req.flags=req.flags or {}
            for flag,value in pairs(negated.flags) do
                if req.flags[flag]~=nil and req.flags[flag]~=value then return nil,"the layer can never be present; check its conditions." end
                req.flags[flag]=value
            end
        end
    end
    return req
end
-- Door keys read "right:512:128". The editor's LuaJ prints any %g as Java's
-- String.valueOf ("512.0"), so whole coordinates use %d, which it keeps.
local function coordinate(v)
    v=tonumber(v) or 0
    return v==math.floor(v) and string.format("%d",v) or tostring(v)
end
function M.build(index,layout,config)
    config=config or {}
    local light_ability=text(config.light_ability)
    if light_ability=="" then light_ability=nil end
    local g={areas={},edges={},rewards={},objectives={},diagnostics={},outgoing={},rewards_by_area={},rooms={}}
    local function diag(severity,code,room,message,object,property)
        g.diagnostics[#g.diagnostics+1]={severity=severity,code=code,room=room,message=message,
            object_id=object and object.object_id,file=object and object.file,property=property or "progression_area"}
    end
    local function area(room,name)
        local key=room .. ":" .. (id(name) or "main")
        if not g.areas[key] then diag("error","missing_progression_area",room,"Unknown logical area " .. key) end
        return key
    end
    local function edge(e)
        if not g.areas[e.from] or not g.areas[e.to] then return end
        g.edges[#g.edges+1]=e; g.outgoing[e.from]=g.outgoing[e.from] or {}; table.insert(g.outgoing[e.from],e)
    end
    local function links(room,value,declared)
        if value==nil or value=="" then return end
        local entries={}
        if type(value)=="string" then
            -- Preserve empty fields so a malformed entry gets exactly one error.
            for entry in (value .. ","):gmatch("(.-),") do entries[#entries+1]=text(entry) end
        else entries={value} end
        for i,entry in ipairs(entries) do
            local from,to,abilities
            local valid=type(entry)=="string" and declared
            if valid then
                local route,requirements=entry:match("^([^=]+)=(.*)$")
                route=route or entry
                from,to=route:match("^%s*([%w_.-]+)%s*>%s*([%w_.-]+)%s*$")
                valid=from and to and g.areas[room .. ":" .. from] and g.areas[room .. ":" .. to]
                abilities={}
                if requirements~=nil then
                    for ability in (requirements .. "+"):gmatch("(.-)%+") do
                        ability=id(ability)
                        if not ability or not ability:match("^[%w_.-]+$") then valid=false
                        else abilities[ability]=true end
                    end
                end
            end
            if valid then
                local req,unknown={abilities={}},nil
                for ability in pairs(abilities) do
                    local err=Rules.require_ability(ability,req,{config=config,diag=diag,object={room=room}},"progression_links")
                    unknown=unknown or err
                end
                edge({id="link:" .. room .. ":" .. i,from=room .. ":" .. from,to=room .. ":" .. to,
                    room=room,requirements=req,unknown=unknown})
            else
                diag("error","invalid_progression_link",room,
                    "Invalid progression link " .. tostring(entry) .. "; use declared areas and from>to[=ability_a+ability_b].",
                    nil,"progression_links")
            end
        end
    end
    for _,r in ipairs(layout.rooms or {}) do
        if not (index.room_set or {})[r.id] then diag("error","missing_progression_room",r.id,"Placed room has no normalized Tiled export.") end
        if g.rooms[r.id] then diag("error","duplicate_layout_room",r.id,"Room occurs more than once in the layout.") end
        local map=index.normalized_maps[r.id] or {}
        local p=Properties.flatten(map.properties or {})
        if light_ability and p.requires_light~=true then
            local darkness
            -- Match the room loader: first numeric property wins, even at zero.
            for _,key in ipairs({"darkness","base_darkness","map_darkness","ambient_darkness"}) do
                darkness=tonumber(p[key])
                if darkness then break end
            end
            if darkness and darkness>=1 then
                diag("warning","dark_room_unmarked",r.id,
                    "Darkness 1 makes this room fully dark in Light mask mode, but requires_light is not set, so the analysis assumes it can be crossed without " .. light_ability .. ".",
                    nil,"requires_light")
            end
        end
        local c=(config.rooms or {})[r.id] or {}
        local names=words(p.progression_areas or c.areas)
        local declared=#names>0
        if #names==0 then names={"main"} end
        local explicit=#names>1 or p.progression_open==true or c.open==true
        for _,name in ipairs(names) do
            if type(name)~="string" or not name:match("^[%w_.-]+$") then
                diag("error","invalid_progression_area",r.id,"Area names use letters, digits, underscore, dot or hyphen.")
                name=tostring(name)
            end
            local key=r.id .. ":" .. name
            if g.areas[key] then diag("error","duplicate_progression_area",r.id,"Duplicate logical area " .. name) end
            g.areas[key]={id=key,room=r.id,name=name}
        end
        g.rooms[r.id]={layout=r,areas=names,doors=assignments(p.progression_doors or c.door_areas),
            explicit=explicit,default=names[1],properties=p}
        links(r.id,p.progression_links,declared)
        if not explicit then diag("warning","geometry_unknown",r.id,"Annotate progression_open or progression_areas; internal movement is unverified.") end
        if p.progression_required==true then g.objectives[#g.objectives+1]={id="room:" .. r.id,area=r.id .. ":" .. names[1],required=true} end
    end
    local function location(o,field)
        local r=g.rooms[o.room]; if not r then return end
        local name=id(o.properties[field or "progression_area"])
        local uncertain=not r.explicit or (#r.areas>1 and not name)
        return area(o.room,name or r.default),uncertain and "Object/door area or room movement is unannotated." or nil
    end
    -- A boss-phase arena hazard acts only during its fight, and Rules.barrier_kinds.hazard gives it no
    -- requirement: it is no barrier, so it needs no endpoints (a rising level keeps its barrier rules).
    local function phase_hazard(o)
        local p=o.properties
        return o.type=="hazard" and (not p.level_mode or p.level_mode=="" or p.level_mode=="none")
            and (id(p.arena_id) or id(p.boss_id))~=nil
    end
    -- Missing gate endpoints must not allow a declared open room to bypass it.
    for _,o in ipairs(index.objects) do
        local r=g.rooms[o.room]
        if r and o.visible and barriers[o.type] and not phase_hazard(o)
            and (not id(o.properties.progression_from) or not id(o.properties.progression_to)) then
            r.explicit=false
            diag("warning","barrier_endpoints_unknown",o.room,"Barrier needs progression_from and progression_to; room traversal is unknown.",o)
        end
    end
    local function door_area(room,door,side)
        local r=g.rooms[room]; if not r then return end
        local key=door and (door.side or side) .. ":" .. coordinate(door.cx) .. ":" .. coordinate(door.cy)
        local name=(key and r.doors[key]) or r.doors[side]
        return area(room,name or r.default),not r.explicit or (#r.areas>1 and not name)
    end
    for room,r in pairs(g.rooms) do for _,name in ipairs(r.areas) do
        g.areas[room .. ":" .. name].unknown=not r.explicit
        if not r.explicit and name~=r.default then
            edge({id="unknown:" .. room .. ":" .. name,from=room .. ":" .. r.default,to=room .. ":" .. name,unknown="Internal barrier endpoints are incomplete."})
            edge({id="unknown:" .. room .. ":" .. name .. ":reverse",to=room .. ":" .. r.default,from=room .. ":" .. name,unknown="Internal barrier endpoints are incomplete."})
        end
    end end
    for _,r in ipairs(layout.rooms or {}) do
        for i,n in ipairs(r.neighbors or {}) do
            if not g.rooms[n.id] then diag("error","missing_neighbor_room",r.id,"Door destination " .. tostring(n.id) .. " is not placed.")
            else
                local from,u=door_area(r.id,n.door,n.side)
                local to,v=door_area(n.id,n.mate,n.mate and n.mate.side)
                edge({id="door:" .. r.id .. ":" .. i,from=from,to=to,unknown=(u or v) and "Door endpoints or internal geometry are unannotated." or nil})
            end
        end
    end
    local teleporters,pairs_by_id,stations={},{},{}
    for _,o in ipairs(index.objects) do if o.visible and g.rooms[o.room] and o.type=="teleporter" then
        local tid=o.relationship_ids and o.relationship_ids.teleporter_id
        if tid then teleporters[tid]=o end
        local pair=id(o.properties.pair_id)
        if pair then pairs_by_id[pair]=pairs_by_id[pair] or {}; table.insert(pairs_by_id[pair],o) end
    end end
    for _,o in ipairs(index.objects) do
        if o.visible and o.top_level and g.rooms[o.room] and
            (o.type=="fast_travel" or (o.type=="save_point" and o.properties.is_fast_travel==true)) then
            stations[#stations+1]=o
        end
    end
    local ctx={id=id,area=area,location=location,edge=edge,diag=diag,graph=g,config=config,
        teleporters=teleporters,pairs_by_id=pairs_by_id,stations=stations}
    -- Use the same structural and final-layout checks as elevator publication.
    -- Only baked, visible markers with known floor areas can prove a route.
    local modeled_elevators = {}
    local marker_objects = {}
    for _, o in ipairs(index.objects) do marker_objects[o.room .. ":" .. tostring(o.object_id)] = o end
    local manifest = require("hooks.core.elevator_manifest").build_from_maps(index.normalized_maps)
    local resolved = require("mvtk.elevators.layout_resolver").resolve(manifest, layout)
    for _, elevator_id in ipairs(resolved.ordered_ids or {}) do
        local elevator = resolved.elevators[elevator_id]
        local markers, floors, valid = {}, {}, elevator.valid and elevator.settings.enabled ~= false
        local function marker(node)
            local o = node and marker_objects[node.source_key]
            if not o or not o.visible or not o.top_level or not g.rooms[o.room] then valid = false
            else markers[#markers + 1] = o end
            return o
        end
        marker(elevator.controller)
        for _, node in ipairs(elevator.nodes or {}) do
            local o = marker(node)
            if o and node.kind == "landing" then
                local at, unknown = location(o)
                if not g.areas[at] then valid = false end
                floors[#floors + 1] = { area = at, unknown = unknown, object = o }
            end
        end
        if valid and #floors >= 2 then
            for _, o in ipairs(markers) do modeled_elevators[o] = true end
            for i = 2, #floors do
                local a, b = floors[i - 1], floors[i]
                local unknown = elevator.settings.activation_mode == "trigger_only"
                    and "Elevator runs only when switched" or a.unknown or b.unknown
                local e = { id = "elevator:" .. elevator_id .. ":" .. i, from = a.area, to = b.area,
                    room = a.object.room, object_id = a.object.object_id, unknown = unknown }
                edge(e)
                local back = Copy(e); back.id = e.id .. ":reverse"; back.from, back.to = b.area, a.area; edge(back)
            end
        end
    end
    for _,o in ipairs(index.objects) do if o.visible and g.rooms[o.room] then
        local p,t=o.properties,o.type
        if (t=="elevator" or t=="elevator_node" or t=="elevator_controller") and not modeled_elevators[o] then
            g.unmodeled_traversal=true
            diag("warning","elevator_route_unknown",o.room,"Persistent elevator movement needs an in-engine traversal check; unreached areas remain unknown.",o)
        end
        local at,uncertain=location(o)
        if not o.top_level then uncertain="Gameplay objects in Tiled groups are not baked as runtime gameplay." end
        local req={abilities={},items={},flags={}}
        local cost={}
        local ability,item,unknown,unlock
        local appear=presence_requirement(p.appear_when)
        local conditioned=appear~=nil or not PresenceCondition.is_blank(p.remove_when)
        if appear==false then uncertain=uncertain or "World-state condition does not parse." end
        ctx.at,ctx.uncertain,ctx.requirements,ctx.cost,ctx.object=at,uncertain,req,cost,o
        ctx.stage_flags=nil
        if t=="locked_door" then
            if p.starts_locked~=false then
                ability=id(p.require_ability); item=id(p.require_key) or id(p.require_item)
                if item and p.consume_key~=false then cost[Keys.canonicalize(item)]=1 end
                -- No requirement can still open by interaction, but external
                -- puzzle triggers are not proved by this geometric analysis.
                if not ability and not item then unknown="Door has no automatic unlock requirement; interaction/puzzle needs playtesting." end
            end
            unlock=id(p.door_id) or o.instance_id
        elseif t=="gate" then
            local kind=id(p.gate_type) or "ability_requirement"
            local defaults=(config.gate_types or {})[kind] or {}
            local runtime_kind=defaults.type or kind
            if runtime_kind=="intangible_barrier" or p.starts_open~=true then
                local rule=Rules.gate_kinds[runtime_kind]
                if rule then unknown=rule(p,defaults,req,cost,ctx)
                else unknown="Gate kind " .. runtime_kind .. " depends on actions, movement, timing or custom logic." end
                if type(defaults.condition)=="function" or defaults.on_unlock then unknown="Custom gate callback requires playtesting." end
            end
            if runtime_kind~="intangible_barrier" and p.stays_open~=false and p.persist_unlock~=false then
                local group_id=text(p.group_id)
                unlock=group_id~="" and "group:"..group_id or id(p.gate_id) or o.instance_id
            end
            local duration=tonumber(defaults.timer_duration or (defaults.interaction or {}).timer_duration) or 0
            if runtime_kind~="intangible_barrier" and (duration>0 or p.persist_unlock==false or p.stays_open==false) then
                unknown="Temporary gate unlock/streaming requires playtesting."
            end
            for _,custom in pairs(config.gates or {}) do
                if type(custom)=="table" and custom.id==(id(p.gate_id) or o.instance_id) then unknown="Instance gate configuration requires playtesting." end
            end
        elseif Rules.barrier_kinds[t] then unknown=Rules.barrier_kinds[t](o,ctx)
        elseif barriers[t] then unknown="Timing, combat, switches or collision geometry require playtesting."
        end
        if ability then
            local err=Rules.require_ability(ability,req,ctx,"require_ability")
            unknown=unknown or err
        end
        if item then req.items[Keys.canonicalize(item)]=1 end
        if barriers[t] then
            local from=id(p.progression_from); local to=id(p.progression_to)
            if from and to then
                local a,b=area(o.room,from),area(o.room,to)
                local e={id=o.instance_id,from=a,to=b,requirements=req,cost=cost,unlock=unlock,
                    unknown=unknown or (not o.top_level and uncertain or nil) or (conditioned and PRESENCE_UNKNOWN or nil),
                    object_id=o.object_id,room=o.room,
                    stage_flags=ctx.stage_flags}
                edge(e)
                if p.progression_one_way~=true then local back=Copy(e); back.id=e.id .. ":reverse"; back.from,back.to=b,a; edge(back) end
            end
        elseif Rules.edges[t] then
            local before=#g.edges
            Rules.edges[t](o,ctx)
            -- A conditioned station, teleporter or route may be absent: its
            -- edges stay possible, never proved.
            if conditioned then
                for i=before+1,#g.edges do g.edges[i].unknown=g.edges[i].unknown or PRESENCE_UNKNOWN end
            end
        end
        local reward={id=o.instance_id,area=at,abilities={},items={},flags={},unknown=uncertain}
        local collectible=(config.collectible_types or {})[p.collectible_type] or {}
        if Rules.unmodeled[t] then
            g.unmodeled_rewards=true
            diag("warning","reward_logic_unknown",o.room,Rules.unmodeled[t],o)
        end
        local handled=Rules.rewards[t] and Rules.rewards[t](o,ctx,reward)
        if not handled and t=="collectible" and (type(collectible.on_collect)=="function" or not next(collectible)) then
            g.unmodeled_rewards=true
            diag("warning","reward_logic_unknown",o.room,"Custom collectible reward is not modeled.",o)
        end
        if next(reward.abilities) or next(reward.items) or next(reward.flags) then
            if appear then reward.requirements=appear end
            if not PresenceCondition.is_blank(p.remove_when) then
                diag("warning","presence_removal_unmodelled",o.room,
                    "remove_when can take this reward away before it is collected; the analysis assumes it stays.",o,"remove_when")
            end
            g.rewards[#g.rewards+1]=reward
            g.rewards_by_area[at]=g.rewards_by_area[at] or {}; table.insert(g.rewards_by_area[at],reward)
        end
        local ending=t=="end_game" and require("mvtk.game.endings").find(config.game_completion or {},p.completion_id)
        if t=="end_game" and (config.game_completion or {}).enabled and ending and ending.enabled~=false and ending.condition=="region" then
            local goal_id="ending:"..tostring(p.completion_id)
            local goal
            for _,candidate in ipairs(g.objectives) do if candidate.id==goal_id and candidate.locations then goal=candidate; break end end
            if not goal then
                goal={id=goal_id,area=at,required=ending==config.game_completion,locations={}}
                g.objectives[#g.objectives+1]=goal
            end
            -- Entering any region with this ending ID completes the same goal.
            -- Keep uncertainty local so a speculative region cannot hide a known route.
            local unknown=uncertain or (g.areas[at] and g.areas[at].unknown)
            if not goal.locations[at] or not unknown then goal.locations[at]={unknown=unknown} end
        end
        if id(p.progression_objective) then g.objectives[#g.objectives+1]={id=p.progression_objective,area=at,required=p.progression_optional~=true,unknown=uncertain,requirements=appear or nil} end
    end end
    -- World-state tile layers (G8-10) with progression_from and progression_to
    -- are barriers between those areas: passable while the layer is absent,
    -- or while present with progression_passable_when_present. Only flag
    -- conditions compile; anything else stays unknown.
    local LayerProps=require "mvtk.tiled.visual_ownership"
    local room_ids={}
    for room in pairs(g.rooms) do room_ids[#room_ids+1]=room end
    table.sort(room_ids)
    for _,room in ipairs(room_ids) do
        for _,layer in ipairs((require("hooks.core.tilemap_split").state_layers(index.normalized_maps[room]))) do
            local tiled=layer.entry.layer
            local where={file="developer/assets/tiled/maps/"..room..".lua"}
            local from,to=id(LayerProps.property_value(tiled,"progression_from")),id(LayerProps.property_value(tiled,"progression_to"))
            if from and to then
                local passable,unknown=state_layer_requirement(layer,
                    LayerProps.property_value(tiled,"progression_passable_when_present")==true
                    or LayerProps.property_value(tiled,"progression_passable_when_present")=="true")
                local e={id="state_layer:"..room..":"..tostring(layer.id),from=area(room,from),to=area(room,to),
                    requirements=passable or {},room=room,
                    unknown=unknown and ("World-state layer '"..layer.name.."': "..unknown) or nil}
                edge(e)
                local back=Copy(e); back.id=e.id..":reverse"; back.from,back.to=e.to,e.from; edge(back)
            elseif layer.collision~="none" then
                -- A decorative layer can legitimately have no endpoints, so the
                -- room's traversal stays as annotated.
                diag("warning","state_layer_barrier_unknown",room,
                    "World-state tile layer '"..layer.name.."' can collide but has no progression_from and progression_to; the analysis ignores it.",
                    where,"progression_from")
            end
        end
    end
    -- Rewards and gates share the loop above. Do not resolve producers early:
    -- a later object (or a future reward rule) may provide a listed flag.
    local produced={}
    for _,reward in ipairs(g.rewards) do
        for flag,value in pairs(reward.flags or {}) do
            if value~=nil and value~=false then produced[flag]=true end
        end
    end
    for _,e in ipairs(g.edges) do
        for _,flag in ipairs(e.stage_flags or {}) do
            if not produced[flag] then
                e.stage_flags_unmodeled=e.stage_flags_unmodeled or {}
                e.stage_flags_unmodeled[flag]=true
            end
        end
    end
    for _,o in ipairs(config.objectives or {}) do g.objectives[#g.objectives+1]=Copy(o) end
    for _,ending in ipairs(require("mvtk.game.endings").list(config.game_completion or {})) do
        if ending.condition~="region" and (layout.rooms or {})[1] then
            local first=layout.rooms[1]; local flag=ending.condition=="boss" and ("boss_defeated_"..tostring(ending.boss_id)) or ending.flag
            g.objectives[#g.objectives+1]={id="ending:"..ending.id,area=first.id..":"..g.rooms[first.id].default,
                anywhere=true,required=ending==config.game_completion,requirements={flags={[flag or ""]=true}}}
            local modeled=false
            for _,reward in ipairs(g.rewards) do if reward.flags and reward.flags[flag] then modeled=true; break end end
            if not modeled then
                g.unmodeled_rewards=true
                diag("warning","ending_flag_source_unknown",nil,"Ending '"..tostring(ending.id).."' flag "..tostring(flag).." has no modeled producer. Verify its gameplay source; use a preview flag to inspect the completed route.")
            end
        end
    end
    -- A missing optional region still has its own objective; authoring reports
    -- its placement issue. It cannot make the main route fail.
    for _,ending in ipairs(require("mvtk.game.endings").list(config.game_completion or {})) do
        local found=false
        for _,goal in ipairs(g.objectives) do if goal.id=="ending:"..ending.id then found=true end end
        if not found and (layout.rooms or {})[1] then
            local first=layout.rooms[1]
            g.objectives[#g.objectives+1]={id="ending:"..ending.id,area=first.id..":"..g.rooms[first.id].default,
                required=ending==config.game_completion,unknown=true}
        end
    end
    for _,ending in ipairs(require("mvtk.game.endings").list(config.game_completion or {})) do
        for _,goal in ipairs(g.objectives) do if goal.id=="ending:"..ending.id then
            local r=type(ending.requires)=="table" and ending.requires or {}
            goal.requirements=goal.requirements or {}; goal.requirements.flags=goal.requirements.flags or {}
            for _,flag in ipairs(type(r.flags)=="table" and r.flags or {}) do
                if type(flag)=="string" then goal.requirements.flags[flag]=true end
            end
            for _,boss in ipairs(type(r.bosses)=="table" and r.bosses or {}) do
                if type(boss)=="string" then goal.requirements.flags["boss_defeated_"..boss]=true end
            end
            if type(r.completion_percent)=="number" or (type(r.max_minutes)=="number" and r.max_minutes>0) then goal.unknown=true end
        end end
    end
    local seen={}
    if light_ability then
        for _,e in ipairs(g.edges) do
            local from=g.rooms[g.areas[e.from].room]
            local to=g.rooms[g.areas[e.to].room]
            if to.properties.requires_light==true and from.properties.requires_light~=true then
                -- Reverse barrier/connection edges can share requirements.
                e.requirements=Copy(e.requirements or {})
                e.requirements.abilities=e.requirements.abilities or {}
                e.requirements.abilities[light_ability]=true
            end
        end
    end
    for _,o in ipairs(g.objectives) do
        if not id(o.id) or seen[o.id] then diag("error","invalid_objective_id",nil,"Objectives need unique, nonempty IDs.") end
        if o.id then seen[o.id]=true end
        if not g.areas[o.area] then diag("error","missing_objective_area",nil,"Objective " .. tostring(o.id) .. " names a missing area.") end
        if not o.locations and not o.anywhere and g.areas[o.area] and g.areas[o.area].unknown then o.unknown="Objective location has unverified internal geometry." end
        for field in pairs(o.requirements or {}) do
            if field~="abilities" and field~="items" and field~="flags" and field~="resources" and field~="any" then
                o.unknown="Unsupported objective condition: " .. field
                diag("warning","objective_condition_unknown",nil,o.unknown)
            end
        end
    end
    local first=(layout.rooms or {})[1]
    g.start=id(config.start) or (first and first.id .. ":" .. g.rooms[first.id].default)
    if g.start and not g.areas[g.start] then diag("error","missing_start_area",nil,"Start area is absent from the layout.") end
    return g
end
return M
