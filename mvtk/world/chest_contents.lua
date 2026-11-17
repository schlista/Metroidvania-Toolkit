-- Shared pure chest parsers: preserve the authored normalization and runtime parsing rules.
local Util = require "mvtk.core.util"
local M = {}

function M.looks_inline_contents(value)
    if type(value) ~= "string" then return false end
    return value:find(":", 1, true) or value:find(",", 1, true) or value:find(";", 1, true)
end

function M.normalize_inline_contents(raw)
    if type(raw) ~= "string" then return nil end
    local items = {}
    for token in raw:gmatch("[^,;]+") do
        local item, amount = token:match("^%s*([^:]+)%s*:%s*(%d+)%s*$")
        if not item then
            item = token:match("^%s*([^:]+)%s*$")
        end
        item = Util.trim(item)
        if item ~= "" then
            local qty = tonumber(amount) or 1
            items[#items + 1] = string.format("%s:%d", item, qty)
        end
    end
    if #items == 0 then
        return nil
    end
    return table.concat(items, ",")
end

-- Parse inline contents format: "type:amount,type:amount" (e.g., "currency:500,health_large:1")
function M.parse_inline_contents(contents_str)
    if not contents_str or contents_str == "" then return nil end

    local items = {}
    for entry in string.gmatch(contents_str, "([^,]+)") do
        local item_type, amount_str = string.match(entry, "([^:]+):?(%d*)")
        if item_type then
            item_type = string.gsub(item_type, "^%s+", "")  -- trim leading spaces
            item_type = string.gsub(item_type, "%s+$", "")  -- trim trailing spaces
            local amount = tonumber(amount_str) or 1
            table.insert(items, { type = item_type, amount = amount })
        end
    end

    return #items > 0 and items or nil
end

return M
