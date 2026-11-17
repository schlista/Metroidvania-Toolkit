-- Session-owned room listener: every destination updates presence, even when
-- it has no region. Display text stays in the generated Steamworks VDF.
local M = {}
local generation = 0
-- The manager already has literal build dependencies elsewhere. Naming this
-- edge avoids a Bob cycle through gameplay_services and room startup.
local ROOM_MANAGER_MODULE = "mvtk.map.streaming.room_manager"

function M.on_session_start()
    generation = generation + 1
    local token = generation
    local Platform = require "mvtk.platform.platform_services"
    Platform.set_rich_presence("playing")
    local manager = require(ROOM_MANAGER_MODULE)
    manager.register_event("on_room_enter", function(room_id)
        if token ~= generation then return end
        local Regions = require "mvtk.world.regions"
        local Tokens = require "mvtk.platform.rich_presence_tokens"
        local id = Regions.of_room(room_id, manager.get_room_data(room_id))
        local info = Regions.info(id)
        if info and Tokens.region_ok(id, info.name) then
            Platform.set_rich_presence("region", id)
        else
            Platform.set_rich_presence("playing")
        end
    end)
end

return M
