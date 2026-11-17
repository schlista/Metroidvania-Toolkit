local Kit = require "hooks.core.bake_kit"
local M = {TYPES={"socket"}}

function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local x,y,_,_,w,h = Kit.rect(C,room,obj,defold_y,48,48,96,96)
    local name = room.id .. "_socket_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go,name),
        C.gen_collision_zone_go("/mvtk/prefabs/socket.script",w,h,96,96,"sensor",{"world"}))
    local id = Kit.opt(C.get_prop_value(obj,"socket_id"))
    if id == "" then id = obj_id end
    local key = Kit.opt(C.get_prop_value(obj,"persist_key"))
    if key == "" then key = room.id .. "_" .. obj.id end
    Kit.instance(C,room,obj_id,C.GENERATED_ROOMS_RESOURCE_DIR.."/"..name,x,y,{
        C.text_prop("socket_id",id,""), C.text_prop("room_id",room.id,""),
        C.text_prop("persist_key",key,""), Kit.text(C,obj,"target_id",""),
        Kit.text(C,obj,"accepts","any"), Kit.text(C,obj,"accepts_id",""),
        Kit.text(C,obj,"message_on","activate"), Kit.text(C,obj,"message_off","deactivate"),
        Kit.bool(C,obj,"persist_state",false), Kit.text(C,obj,"set_flag_on",""),
    })
    return true
end
return M
