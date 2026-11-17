-- Whole-table overrides shared by runtime and authoring tools.
-- Each caller supplies its own loader, including sandboxed script test hosts.
local M = {}
local EMPTY = {}
local cached_base, cached_authored, cached_tables, cached_origin

function M.merge(base, authored)
    local merged, origin = {}, {}
    for id, entry in pairs(type(base) == "table" and base or EMPTY) do
        merged[id], origin[id] = entry, "base"
    end
    for id, entry in pairs(type(authored) == "table" and authored or EMPTY) do
        if type(entry) == "table" then
            merged[id], origin[id] = entry, "authored"
        end
    end
    return merged, origin
end

function M.load(loader)
    local ok_base, base = pcall(loader, "developer.config.loot_tables")
    local ok_authored, authored = pcall(loader, "developer.config.loot_tables_authored")
    base = ok_base and type(base) == "table" and base or EMPTY
    authored = ok_authored and type(authored) == "table" and authored or EMPTY
    if base ~= cached_base or authored ~= cached_authored then
        cached_tables, cached_origin = M.merge(base, authored)
        cached_base, cached_authored = base, authored
    end
    return cached_tables, cached_origin
end

return M
