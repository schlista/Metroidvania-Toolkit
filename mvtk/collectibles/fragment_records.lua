-- Records registration is deferred until session start: strict loaders need no dependencies.
local M = {}

function M.section(deps)
    deps = deps or {}
    local function rows()
        local config = deps.config or require("mvtk.collectibles.fragments").settings()
        local Flags = deps.flags or require "mvtk.core.flags"
        local Types = deps.types or require "developer.config.collectible_types"
        local placed = {}
        for _, entry in ipairs((deps.census or require "mvtk.world.census").entries()) do
            local def = Types[entry.type] or {}
            if entry.kind == "item" and def.on_collect == "add_fragment" then placed[def.fragment_set] = true end
        end
        local ids, out = {}, {}
        for id in pairs(config.sets or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local set = config.sets[id]
            local count = Flags.get("fragment_count_" .. id, 0)
            if placed[id] or count > 0 then
                out[#out + 1] = {label = set.name, value = {
                    forms = {one = "journal.progress_one", other = "journal.progress_other"},
                    count = set.pieces, params = {found = count % set.pieces, total = set.pieces}}}
            end
        end
        return out
    end
    return {id = "fragments", order = 35,
        header = function() return {key = "records.fragments"} end,
        lines = rows, visible = function() return #rows() > 0 end}
end

function M.on_session_start()
    require("mvtk.ui.screens.journal_records").add_section(M.section())
end

return M
