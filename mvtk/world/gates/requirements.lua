-- Pure requirement evaluation shared by runtime gates and authoring analysis.
-- Callbacks read live state; table fields provide a side-effect-free snapshot.
local M = {}
-- Counts use the same truth semantics as req.flags=true (including 0/text).
function M.count_progress(count, flags)
    local current = 0
    local list = count.flags or {}
    local need = tonumber(count.need) or 0
    if need <= 0 then need = #list end
    need = math.min(math.floor(need), #list)
    for _, id in ipairs(list) do
        local value = (flags or {})[id]
        if value ~= nil and value ~= false then current = current + 1 end
    end
    return current, need
end
function M.evaluate(req, state)
    req, state = req or {}, state or {}
    local missing = {}
    for id in pairs(req.abilities or {}) do
        local has
        if state.has_ability then has=state.has_ability(id) else has=(state.abilities or {})[id] end
        if not has then missing[#missing+1] = "ability: " .. id end
    end
    for id, amount in pairs(req.items or {}) do
        local has = state.has_item and state.has_item(id, amount)
        if not state.has_item then has = ((state.items or {})[id] or 0) >= amount end
        if not has then missing[#missing+1] = "item: " .. id .. " x" .. amount end
    end
    for id, expected in pairs(req.flags or {}) do
        local value = (state.flags or {})[id]
        if expected == true then value = value ~= nil and value ~= false
        elseif value == nil then value = false end
        if value ~= expected then missing[#missing+1] = "flag: " .. id .. "=" .. tostring(expected) end
    end
    for id, amount in pairs(req.resources or {}) do
        if ((state.resources or {})[id] or 0) < amount then missing[#missing+1] = "resource: " .. id .. " x" .. amount end
    end
    for _, count in ipairs(req.counts or {}) do
        local current, need = M.count_progress(count, state.flags)
        if current < need then
            missing[#missing+1] = "flags: " .. current .. "/" .. need .. " of " .. table.concat(count.flags or {}, ", ")
        end
    end
    if req.any then
        local alternatives, passed = {}, false
        for _, alternative in ipairs(req.any) do
            local ok, reasons = M.evaluate(alternative, state)
            if ok then passed = true; break end
            alternatives[#alternatives+1] = table.concat(reasons, ", ")
        end
        if not passed then
            table.sort(alternatives)
            missing[#missing+1] = "any of: " .. table.concat(alternatives, " | ")
        end
    end
    table.sort(missing)
    return #missing == 0, missing
end
return M
