-- Hit acceptance and side classification; health and world changes belong to the caller.
local M = {}

-- An explicit requirement overrides the wall type's default.
function M.required_ability(required, wall_type)
    if required and required ~= "" then return required end
    if wall_type == "bomb_only" then return "bomb" end
end

-- families may hold type definitions ({family=...}) or direct family ids.
function M.damage_type_ok(required, dtype, families)
    if required == nil or required == "" or required == "none" then return true end
    if dtype == nil or dtype == "" or dtype == "contact" then dtype = "physical" end
    local seen = {}
    while type(dtype) == "string" and not seen[dtype] do
        if required == dtype then return true end
        seen[dtype] = true
        local entry = (families or {})[dtype]
        dtype = type(entry) == "table" and entry.family or entry
    end
    return false
end

function M.accepts(required_ability, wall_type, attack_type, tags, damage)
    damage = damage or 1
    if (not required_ability or required_ability == "") and wall_type == "bomb_only" then
        required_ability = M.required_ability(required_ability, wall_type)
        if not tags or next(tags) == nil then tags = { bomb = true } end
    end
    if required_ability and required_ability ~= "" then
        local matches = false
        if type(attack_type) == "string" then
            matches = attack_type ~= "" and (tags or {})[attack_type] == true
        elseif type(attack_type) == "userdata" then
            -- Hash forward: release builds need not retain the original text.
            for tag, enabled in pairs(tags or {}) do
                if enabled and attack_type == hash(tag) then
                    matches = true
                    break
                end
            end
        end
        if not matches then return false, false, 0 end
        local bomb = attack_type == "bomb" or (type(attack_type) == "userdata" and attack_type == hash("bomb"))
        return true, wall_type == "bomb_only" and (required_ability == "bomb" or bomb), math.max(1, damage)
    end
    if damage <= 0 then return false, false, 0 end
    return true, false, damage
end

-- Compare position against a rectangle's normalized half extents. Horizontal
-- wins corner ties. Shots and bombs carry the player as their source actor.
-- With no usable position, knockback points away from the attacking side.
function M.hit_side(wall_pos, half_w, half_h, attacker_pos, kx, ky)
    if wall_pos and attacker_pos then
        local dx, dy = attacker_pos.x - wall_pos.x, attacker_pos.y - wall_pos.y
        if dx ~= 0 or dy ~= 0 then
            local nx = math.abs(dx) / math.max(tonumber(half_w) or 0, 0.001)
            local ny = math.abs(dy) / math.max(tonumber(half_h) or 0, 0.001)
            if nx >= ny then return dx < 0 and "left" or "right" end
            return dy > 0 and "above" or "below"
        end
    end
    kx, ky = tonumber(kx) or 0, tonumber(ky) or 0
    if kx == 0 and ky == 0 then return nil end
    if math.abs(kx) >= math.abs(ky) then return kx > 0 and "left" or "right" end
    return ky > 0 and "below" or "above"
end

return M
