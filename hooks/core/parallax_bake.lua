-- Bake independent scenery GOs and split visual tile layers. No runtime spawning.
local Proto = require "mvtk.editor.proto_utils"
local Background = require "mvtk.editor.background_atlas"
local Props = require "mvtk.tiled.visual_ownership"
local Repeat = require "mvtk.tiled.parallax_repeat"
local Split = require "hooks.core.tilemap_split"
local SharedProto = require "mvtk.editor.shared_proto"
local M = {}

local function quote(s) return '"' .. Proto.proto_escape(s) .. '"' end
local function number(n)
    n = n or 0
    local scaled = math.floor(math.abs(n) * 1000000 + 0.5)
    -- Keep negative zero too: clip offsets previously emitted "-0.000000".
    local negative = n < 0 or (n == 0 and 1 / n < 0)
    return (negative and "-" or "") .. string.format("%d.%06d", math.floor(scaled / 1000000), scaled % 1000000)
end
local function moving(x,y) return x ~= 1 or y ~= 1 end
local function vector(...)
    local values={...}; for i,v in ipairs(values) do values[i]=number(v) end
    return table.concat(values,", ")
end

local function script(map, x, y, fx, fy, clip, opacity, stretch_to_fill)
    local w,h=(map.width or 0)*(map.tilewidth or 0),(map.height or 0)*(map.tileheight or 0)
    local ox,oy=Repeat.map_origin(map)
    local rows={'components {','  id: "parallax"','  component: "/mvtk/tiled/parallax_motion.script"'}
    local properties={
        {"factor_x",number(fx),"NUMBER"},{"factor_y",number(fy),"NUMBER"},
        {"anchor_offset",vector(ox-x,oy-y,0),"VECTOR3"},
        {"clip_offset",vector(-x,-y,w-x,h-y),"VECTOR4"},
        {"clip_sprite",tostring(clip),"BOOLEAN"},{"opacity",number(opacity or 1),"NUMBER"},
    }
    if stretch_to_fill == true then
        properties[#properties+1] = {"stretch_to_fill", "true", "BOOLEAN"}
    end
    for _,p in ipairs(properties) do
        rows[#rows+1]='  properties {\n    id: '..quote(p[1])..'\n    value: '..quote(p[2])..'\n    type: PROPERTY_TYPE_'..p[3]..'\n  }'
    end
    rows[#rows+1]='}\n'
    return table.concat(rows,"\n")
end

-- `overrides` (optional) is component_properties text, after position in
-- InstanceDesc field order.
local function instance(rows,id,path,x,y,z,overrides)
    rows[#rows+1]='instances {\n  id: '..quote(id)..'\n  prototype: '..quote(path)..
        '\n  position {\n    x: '..number(x)..'\n    y: '..number(y)..'\n    z: '..number(z)..'\n  }\n'..
        (overrides and '  '..overrides..'\n' or '')..'}'
end

-- Each image object (including repeat copies) gets its own baked GO. Static
-- images also need initialization for room clipping and inherited opacity.
function M.sprites(context, rows, rid, map, components)
    -- CP05d/e: every motion value of an image (factors, anchor and clip
    -- offsets, opacity) is an instance override; the lean prototype goes
    -- through the shared store; the instance stays baked.
    for _,comp in ipairs(components) do
        local fx,fy=tonumber(comp.parallaxx) or 1,tonumber(comp.parallaxy) or 1
        local visual={}; for k,v in pairs(comp) do visual[k]=v end
        visual.id="sprite"; visual.pos_x=0; visual.pos_y=0; visual.pos_z=0
        local id=rid.."_"..comp.id
        local content=context.gen_backgrounds_go(rid,{visual}).."\n"..
            script(map,comp.pos_x,comp.pos_y,fx,fy,true,comp.opacity,comp.stretch_to_fill)
        local lean,overrides,moved=SharedProto.lift(content,{"parallax"})
        local path=SharedProto.store_checked(context,id,content,lean,moved)
        instance(rows,id,path,comp.pos_x,comp.pos_y,comp.pos_z,overrides)
    end
    return {}
end

-- Preserve complete protobuf layer blocks (including tile: 0 and flip flags).
function M.split_tiles(map,text,settings)
    local selected={}
    for _,entry in ipairs(Background.flatten_tiled_layers(map.layers)) do
        local layer=entry.layer
        if layer.type=="tilelayer" and moving(entry.parallaxx,entry.parallaxy) then
            local visual=(settings.tile_layers or {})[layer.name] or Props.property_value(layer,"parallax_visual")==true
            assert(visual,"Parallax on gameplay tile layer '"..tostring(layer.name).."' is unsupported; keep it at 1 or mark decorative artwork parallax_visual=true")
            assert(not selected[layer.name],"Duplicate moving tile layer: "..tostring(layer.name))
            selected[layer.name]=entry
        end
    end
    return Split.split(text,selected)
end

-- The single main-text path: parallax layers leave first, then world-state
-- layers (G8-10). Returns the main text, the parallax parts, the state parts
-- and the room tilemap text it read.
local function tile_plan(context,rid,map)
    local text=context.read_text(context.join(context.PATH.tilemaps,rid..".tilemap"))
    if not text then return nil,{},{} end
    map=map or context.load_tiled_export(rid)
    if not map then return text,{},{},text end
    local settings=context.load_project_lua_table("developer/config/parallax_settings.lua") or {tile_layers={}}
    local main,parts=M.split_tiles(map,text,settings)
    local selected={}
    for _,record in ipairs((Split.state_layers(map))) do selected[record.name]=record end
    local state_parts
    main,state_parts=Split.split(main,selected)
    return main,parts,state_parts,text
end
M.tile_plan = tile_plan

function M.prepare_tiles(context,rid)
    local text,parts,state_parts=tile_plan(context,rid)
    if #parts==0 and #state_parts==0 then return nil end
    local resource=SharedProto.generated_dir(context).."/"..rid.."_static.tilemap"
    context.write_if_changed(context.join(context.ROOT,resource:sub(2)),text)
    return resource
end

function M.main_tilemap_text(context,rid)
    local text=tile_plan(context,rid)
    return text
end

function M.append_tiles(context,rows,rid,map)
    local _,parts=tile_plan(context,rid,map)
    for _,part in ipairs(parts) do
        local id=Repeat.tile_instance_id(rid,part.entry.layer.id)
        local resource=SharedProto.generated_dir(context).."/"..id
        context.write_if_changed(context.join(context.ROOT,resource:sub(2)..".tilemap"),part.text)
        local content='components {\n  id: "tilemap"\n  component: '..quote(resource..".tilemap")..'\n}\n'..
            script(map,0,0,part.entry.parallaxx,part.entry.parallaxy,false)
        context.write_if_changed(context.join(context.ROOT,resource:sub(2)..".go"),content)
        instance(rows,id,resource..".go",0,0,0)
    end
end

M.motion_script = script
return M
