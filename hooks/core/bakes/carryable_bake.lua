local Kit = require "hooks.core.bake_kit"
local P = require "mvtk.editor.proto_utils"
local M = {TYPES={"carryable"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local x,y,_,_,w,h = Kit.rect(C,room,obj,defold_y,32,32,64,64)
    local co = 'type: COLLISION_OBJECT_TYPE_KINEMATIC\nmass: 0\nfriction: 0.6\nrestitution: 0\n'
        .. 'group: "world"\nmask: "player"\nmask: "sensor"\nmask: "solid"\n'
        .. 'embedded_collision_shape { shapes { shape_type: TYPE_BOX position {} rotation { w: 1 } index: 0 count: 3 } '
        .. 'data: '..P.fmt_num(w/2)..' data: '..P.fmt_num(h/2)..' data: 10 }\n'
    local sprite = 'default_animation: "wall_base"\nsize_mode: SIZE_MODE_MANUAL\nsize { x: '..P.fmt_num(w)..' y: '..P.fmt_num(h)..' }\n'
        .. 'textures { sampler: "texture_sampler" texture: "/developer/assets/atlas/gameplay_visuals.atlas" }\n'
    local text = 'components { id: "script" component: "/mvtk/prefabs/carryable.script" }\n'
        .. 'embedded_components { id: "co" type: "collisionobject" data: "'..P.proto_escape(co)..'" }\n'
        .. 'embedded_components { id: "sprite" type: "sprite" data: "'..P.proto_escape(sprite)..'" }\n'
    local name = room.id.."_carryable_"..obj.id..".go"
    C.write_if_changed(C.join(C.PATH.generated_go,name),text)
    local id = Kit.opt(C.get_prop_value(obj,"carry_id"))
    if id == "" then id = obj_id end
    Kit.instance(C,room,obj_id,C.GENERATED_ROOMS_RESOURCE_DIR.."/"..name,x,y,{
        C.text_prop("carry_id",id,""), C.text_prop("room_id",room.id,""),
        Kit.text(C,obj,"kind","crate"), Kit.text(C,obj,"label","Pick up"),
        Kit.number(C,obj,"move_speed_mult",0.8), Kit.bool(C,obj,"blocks_jump",false),
        Kit.number(C,obj,"throw_speed",900), Kit.bool(C,obj,"breaks_on_impact",false),
        Kit.number(C,obj,"break_speed",1600), Kit.number(C,obj,"fuse_time",3),
        C.number_prop("half_w",w/2,32), C.number_prop("half_h",h/2,32),
    })
    return true
end
return M
