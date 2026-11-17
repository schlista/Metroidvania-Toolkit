-- Shared loot-table selection; keep the older drops spelling for authored projects.
local M = {}

function M.entries(loot)
    return loot.items or loot.drops or {}
end

-- Roll once per entry before RewardDrops expands its amount into pickups.
function M.roll(loot, random)
    random = random or math.random
    local rolled = {}
    for _, entry in ipairs(M.entries(loot)) do
        if random() <= (entry.chance or 1) then
            rolled[#rolled + 1] = entry
        end
    end
    return rolled
end

return M
