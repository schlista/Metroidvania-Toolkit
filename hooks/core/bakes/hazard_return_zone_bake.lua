local Kit = require "hooks.core.bake_kit"
local M = {TYPES={"hazard_return_zone"}}
function M.bake(C, room, obj, obj_type, obj_id, defold_y)
    local px, py, _, _, w, h = Kit.rect(C,room,obj,defold_y,96,64,192,128)
    local name = room.id .. "_hazard_return_zone_" .. obj.id .. ".go"
    C.write_if_changed(C.join(C.PATH.generated_go,name),
        C.gen_collision_zone_go("/mvtk/prefabs/hazard_return_zone.script",w,h,192,128))
    local id = Kit.opt(C.get_prop_value(obj,"return_zone_id"))
    if id == "" then id = obj_id end
    Kit.instance(C,room,obj_id,C.GENERATED_ROOMS_RESOURCE_DIR .. "/" .. name,px,py,{
        C.text_prop("return_zone_id",id,""),C.text_prop("room_id",room.id,""),
        C.number_prop("zone_width",w,192),C.number_prop("zone_height",h,128),
        Kit.number(C,obj,"return_facing",0),Kit.bool(C,obj,"forget_return_point",false)})
    return true
end
return M
