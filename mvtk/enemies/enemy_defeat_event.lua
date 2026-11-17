-- Flat defeat identity shared with the later defeat-record service.
local M = {}
local function text(value) return type(value) == "string" and value or "" end
function M.payload(self, pos)
    return {
        enemy_type = text(self.enemy_type), archetype = text(self.archetype), elite = self.elite == true,
        room_id = text(self._room_id), spawn_id = text(self.spawn_id), group_id = text(self.group_id),
        spawn_owner = "", defeat_key = "", x = pos.x, y = pos.y,
    }
end
return M
