-- Whole-sequence overrides shared by runtime and authoring tools.
-- Callers load their own data so sandboxed and test loaders stay isolated.
local M = {}

function M.merge(static, authored)
    local merged, origin = {}, {}
    for id, sequence in pairs(type(static) == "table" and static or {}) do
        merged[id], origin[id] = sequence, "static"
    end
    for id, sequence in pairs(type(authored) == "table" and authored or {}) do
        if type(sequence) == "table" then
            merged[id], origin[id] = sequence, "authored"
        end
    end
    return merged, origin
end

return M
