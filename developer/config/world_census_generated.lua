-- Generated world census. DO NOT EDIT; run Prepare & Check.
local R = {}
local rooms = {}
for id, build in pairs(R) do rooms[id] = build() end
return {version=1, rooms=rooms}
