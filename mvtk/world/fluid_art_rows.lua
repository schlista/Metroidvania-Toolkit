-- Capture at the fixed drawn rectangle, including the raised extent, before
-- changing any cells. Streaming failures retry from that same world origin.
local Level = require "mvtk.world.fluid_level"
local Transfer = require "mvtk.prefabs.tile_transfer"
local RoomManager = require "mvtk.map.streaming.room_manager"
local Layers = require "mvtk.rooms.tilemap_layers"
local M = {}
function M.new(self, origin, max_height)
    return {origin=vmath.vector3(origin), bottom=origin.y-self.height/2,
        width=self.width, height=max_height, layer=self.level_art_layer,
        tile_height=self.tile_height}
end
local function capture(art)
    if art.cells ~= nil then return true end
    if art.layer == "" then art.cells=false; return true end
    local room = RoomManager.get_room_for_position(art.origin)
    if not room then return false end
    local url, pos = RoomManager.get_tilemap_url(room)
    if not url or not pos then return false end
    local _, lookup = Layers.for_url(url, room)
    if lookup and not lookup[art.layer] then art.cells=false; return true end
    local settings = require("mvtk.core.util").require_config("developer.config.tile_settings") or {}
    local tw, th = tonumber(settings.width) or art.tile_height, art.tile_height
    local cells = Transfer.collect_room_rectangle({room_tilemap_url=url, source_layer=art.layer,
        min_tx=math.floor((art.origin.x-art.width/2-pos.x)/tw)+1,
        max_tx=math.ceil((art.origin.x+art.width/2-pos.x)/tw),
        min_ty=math.floor((art.bottom-pos.y)/th)+1,
        max_ty=math.ceil((art.bottom+art.height-pos.y)/th)})
    if not cells then return false end
    for _, cell in ipairs(cells) do
        -- get_tile_info and set_tile report a missing layer or cell by
        -- returning nil/false, not by raising.
        local ok, info = pcall(tilemap.get_tile_info, url, cell.layer, cell.x, cell.y)
        if not ok or type(info) ~= "table" then return false end
        cell.transform = (info.h_flip and tilemap.H_FLIP or 0)
            + (info.v_flip and tilemap.V_FLIP or 0) + (info.rotate_90 and tilemap.ROTATE_90 or 0)
        cell.middle = pos.y + (cell.y-0.5)*th
    end
    art.url, art.cells = url, cells
    return true
end
function M.apply(art, surface)
    if not capture(art) then return false end
    if art.cells == false then return true end
    local settled = true
    for _, cell in ipairs(art.cells) do
        local visible = Level.row_visible(surface, cell.middle)
        if cell.visible ~= visible then
            local ok, applied = pcall(tilemap.set_tile, art.url, cell.layer, cell.x, cell.y,
                visible and cell.tile_id or 0, cell.transform)
            if ok and applied ~= false then cell.visible=visible else settled=false end
        end
    end
    return settled
end
return M
