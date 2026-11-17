-- Retain passage only for a player who entered while intangibility was active.
local M = {}

function M.next_inside(player_nearby, inside, active)
    return player_nearby == true and (inside == true or active == true)
end

function M.collision_enabled(active, inside)
    return not (active == true or inside == true)
end

return M
