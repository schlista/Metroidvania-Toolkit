-- Registration only at boot; the builder loads after the editor context exists.
local M = {id="world_census",path="developer/config/world_census_generated.lua",
    module="mvtk.editor.room_catalogs.world_census",types="*"}
function M.new_acc() return {} end
function M.collect() end
function M.render(acc,ctx)
    if ctx and not ctx.index then return nil end
    local Builder=require "developer.tools.world_census"
    if not ctx then return Builder.encode({rooms={}}),0 end
    local collections={}
    for _,room in ipairs(ctx.room_ids) do
        collections[room]=ctx.read(ctx.root.."/developer/rooms/collections/"..room..".collection")
    end
    local fresh=require("mvtk.editor.fresh_config").new({root=ctx.root,read=ctx.read})
    local configs=require("mvtk.enemies.enemy_respawn_policy").load_configs(fresh.load_path)
    configs.npc_types=fresh.load_path("developer/config/npc_types.lua") or {}
    local census=Builder.build(ctx.index,collections,{room_ids=ctx.room_ids,configs=configs})
    local count=0;for _,entries in pairs(census.rooms) do count=count+#entries end
    return Builder.encode(census),count
end
return M
