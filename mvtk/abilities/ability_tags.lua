-- Static hit tags shared by runtime requirements and authoring tools.
-- Pass raw action/attack data and the id-keyed ability registry; no live state.
local M = {}

M.CORE_TAGS = { light_attack = true, heavy_attack = true }

-- All authored hit emitters, independent of starting unlocks or live state.
-- The zero-damage parry stun supplies its synthetic tag at the damage boundary.
function M.hit_tags(actions, combat_attacks, carry_settings)
    local tags = {parry = true}
    local function include(tag)
        if type(tag) == "string" and tag ~= "" then tags[tag] = true end
    end
    for _, action in pairs(actions or {}) do
        include(action.action_tag)
        include((action.contact_attack or {}).action_tag)
    end
    for _, attack in pairs(combat_attacks or {}) do include(attack.action_tag) end
    for _, kind in pairs((carry_settings or {}).kinds or {}) do include(kind.hit_tag) end
    return tags
end

local function add(emitted, tag, id)
    if type(tag) ~= "string" or tag == "" then return end
    local ids = emitted[tag]
    if not ids then
        ids = {}
        emitted[tag] = ids
    end
    ids[id] = true
end

function M.emitters(actions, combat_attacks, ability_ids)
    local emitted = {}
    for id in pairs(ability_ids or {}) do
        local action = (actions or {})[id]
        if action then
            add(emitted, action.action_tag, id)
            add(emitted, (action.contact_attack or {}).action_tag, id)
        end
    end
    for _, attack in pairs(combat_attacks or {}) do
        local tag = attack.action_tag
        if tag and (ability_ids or {})[tag] then add(emitted, tag, tag) end
    end
    local result = {}
    for tag, ids in pairs(emitted) do
        local list = {}
        for id in pairs(ids) do list[#list + 1] = id end
        table.sort(list)
        result[tag] = list
    end
    return result
end

-- Forward matching retains the authored id even when it emits no hit itself.
function M.tags_for(id, actions, combat_attacks, ability_ids)
    local tags = {}
    if type(id) ~= "string" or id == "" then return tags end
    tags[id] = true
    for tag, ids in pairs(M.emitters(actions, combat_attacks, ability_ids)) do
        for _, emitter in ipairs(ids) do
            if emitter == id then tags[tag] = true end
        end
    end
    return tags
end

-- Reverse matching describes real hits only, without an own-id fallback.
function M.abilities_for_tag(tag, actions, combat_attacks, ability_ids)
    return M.emitters(actions, combat_attacks, ability_ids)[tag] or {}
end

return M
