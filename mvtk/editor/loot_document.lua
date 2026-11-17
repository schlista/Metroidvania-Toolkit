-- Pure loot editing model. Callers own disk reads, reference snapshots and writes.
local Fresh = require "mvtk.editor.fresh_config"
local Sources = require "mvtk.game.loot_tables_source"
local Model = require "mvtk.core.creator_settings_model"
local M = {}
local STATIC = "developer/config/loot_tables.lua"
local AUTHORED = "developer/config/loot_tables_authored.lua"
local HEADER = "-- Loot tables written by Project > Loot Tables....\n"
    .. "-- A key here replaces the loot_tables.lua table with the same id; loot_tables.lua is never rewritten.\n"
    .. "-- items: { type = collectible type id, amount = whole number >= 1, chance = 0 to 1 }.\n"

local function valid_id(id)
    -- Same ASCII key rule as CatalogEnums.check_values.
    return type(id) == "string" and id ~= "" and not id:find("[^A-Za-z0-9_.-]")
end

local function refresh(doc)
    doc.merged, doc.origin = Sources.merge(doc.static, doc.authored)
    return doc
end

function M.load(opts)
    local root = tostring(opts.root or "."):gsub("\\", "/"):gsub("/$", "")
    local authored_text, authored_missing = nil, false
    local loader = Fresh.new({root=root, read=function(path)
        local text = opts.read(path)
        if path == root .. "/" .. AUTHORED then
            authored_text, authored_missing = text, text == nil
        end
        return text
    end})
    local static, err = loader.load_path(STATIC)
    if not static then return nil, err end
    -- Older projects may not have this optional file. Malformed existing files
    -- still fail to load; they must never be mistaken for an empty document.
    local authored, authored_err = loader.load_path(AUTHORED)
    if not authored and not authored_missing then return nil, authored_err end
    return refresh({static=static, authored=authored or {}, authored_text=authored_text})
end

function M.set(doc, id, value)
    if not valid_id(id) then return nil, "Use a nonempty id containing letters, digits, _, . or -." end
    if type(value) ~= "table" then return nil, "A loot table must be a table." end
    -- Copy the entire replacement, including fields this editor cannot edit.
    doc.authored[id] = Model.copy(value)
    return refresh(doc)
end

function M.remove(doc, id)
    doc.authored[id] = nil
    return refresh(doc)
end

-- Reverting removes only the authored replacement; there are no tombstones.
function M.revert(doc, id) return M.remove(doc, id) end

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys, function(a,b)
        if type(a) == type(b) and (type(a) == "string" or type(a) == "number") then return a < b end
        return type(a) .. tostring(a) < type(b) .. tostring(b)
    end)
    return keys
end

-- types is the values array returned by CatalogEnums.derive for collectibles.
function M.validate(doc, types)
    local allowed = {}
    for _, id in ipairs(types or {}) do allowed[id] = true end
    local out = {}
    local function issue(code, severity, id, item, field, message)
        out[#out+1] = {code=code, severity=severity, id=id, item=item, field=field, message=message}
    end
    local candidates = Model.copy(doc.merged)
    -- A malformed authored replacement must not disappear behind a valid baseline.
    for id, value in pairs(doc.authored) do candidates[id] = value end
    for _, id in ipairs(sorted_keys(candidates)) do
        local value = candidates[id]
        if not valid_id(id) then issue("invalid_id", "error", id, nil, nil,
            "Use a nonempty id containing letters, digits, _, . or -.") end
        if type(value) ~= "table" or type(value.items) ~= "table" then
            issue("invalid_items", "error", id, nil, nil, "A loot table needs an items table (which may be empty).")
        else
            local seen = {}
            for i, item in ipairs(value.items) do
                if type(item) ~= "table" then
                    issue("invalid_item", "error", id, i, nil, "An item must be a table.")
                else
                    if not allowed[item.type] then
                        issue("unknown_type", "error", id, i, "type", "Choose a collectibles catalog type.")
                    elseif seen[item.type] then
                        issue("duplicate_type", "warning", id, i, "type", "This type occurs twice; bosses keep only one drop per type.")
                    end
                    if allowed[item.type] then seen[item.type] = true end
                    -- Shipped tables omit these fields to use the runtime default of 1.
                    local amount = item.amount == nil and 1 or item.amount
                    local chance = item.chance == nil and 1 or item.chance
                    if type(amount) ~= "number" or amount ~= amount or amount < 1 or amount == math.huge or amount % 1 ~= 0 then
                        issue("invalid_amount", "error", id, i, "amount", "Amount must be a whole number of at least 1.")
                    end
                    if type(chance) ~= "number" or chance ~= chance or chance < 0 or chance > 1 then
                        issue("invalid_chance", "error", id, i, "chance", "Chance must be between 0 and 1.")
                    end
                end
            end
        end
    end
    return out
end

-- Dotted ids can alias nested paths ("story.1" and story[1]). Keep only the
-- encoder's top-level comments. Track quoted strings so a multiline text value
-- containing an indented comment-like line is preserved byte for byte.
local function table_comments(source)
    local rows, quoted = {}, false
    for row in (source .. "\n"):gmatch("(.-)\n") do
        local indent = not quoted and row:match("^( +)%-%- ")
        if not indent or #indent == 4 then
            rows[#rows+1] = row
            local escaped = false
            for i = 1, #row do
                local char = row:sub(i, i)
                if escaped then escaped = false
                elseif quoted and char == "\\" then escaped = true
                elseif char == '"' then quoted = not quoted end
            end
        end
    end
    return table.concat(rows, "\n")
end

-- Pass doc.static to identify overrides of this freshly loaded project.
-- Without it every table is described as newly added.
function M.serialize(authored, static)
    local comments = {}
    for id in pairs(authored) do
        assert(valid_id(id), "Cannot serialize an invalid loot id")
        comments[id] = static and static[id] ~= nil and ("Replaces loot_tables.lua's " .. id .. ".")
            or "Added in the Loot Table Editor."
    end
    return HEADER .. "return " .. table_comments(Model.encode(authored, comments)) .. "\n"
end

return M
