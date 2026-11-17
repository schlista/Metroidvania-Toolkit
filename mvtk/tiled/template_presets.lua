-- Shared, pure lookup for curated bases named by template presets.
local Index = require "mvtk.tiled.template_index"
local M = {}

function M.base(value)
    if type(value) ~= "string" then return nil end
    local id = value:match("^%s*(.-)%s*$"):gsub("\\", "/")
    id = id:gsub("^tiled/templates/", ""):gsub("%.tx$", "")
    return Index[id]
end

function M.type_of(value)
    local base = M.base(value)
    return base and base.type or nil
end

return M
