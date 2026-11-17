-- Pure authoring links. Explicit room-local links win over containment.
local Properties = require "mvtk.tiled.property_flattener"
local Proto = require "mvtk.editor.proto_emit"
local M = {}

local function text(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

function M.id(room, object)
    local value = text(Properties.flatten(object.properties or {}).encounter_id)
    return value ~= "" and value or Proto.generated_object_id(room, "encounter", object.id)
end

function M.collect(map)
    local encounters, spawns = {}, {}
    for _, layer in ipairs((map or {}).layers or {}) do
        if layer.name == "templates" and layer.visible ~= false then
            for _, object in ipairs(layer.objects or {}) do
                if object.visible ~= false then
                    local p = Properties.flatten(object.properties or {})
                    local kind = object.type or object.class or ""
                    if kind == "" then
                        kind = p.encounter_wave ~= nil and "encounter_spawn"
                            or p.encounter_start ~= nil and "encounter" or ""
                    end
                    if kind == "encounter" then encounters[#encounters+1] = object
                    elseif kind == "encounter_spawn" then spawns[#spawns+1] = object end
                end
            end
        end
    end
    return encounters, spawns
end

function M.resolve(room, spawn, encounters)
    local p = Properties.flatten(spawn.properties or {})
    local ref = p.encounter_ref
    local numeric = tonumber(type(ref) == "table" and ref.id or ref)
    if numeric == 0 then numeric = nil end
    local explicit = text(p.encounter_id)
    local best, best_area
    for _, object in ipairs(encounters or {}) do
        if (numeric and tonumber(object.id) == numeric)
            or (not numeric and explicit ~= "" and M.id(room, object) == explicit) then
            return M.id(room, object)
        end
        if not numeric and explicit == "" then
            local x, y = tonumber(spawn.x) or 0, tonumber(spawn.y) or 0
            local ox, oy = tonumber(object.x) or 0, tonumber(object.y) or 0
            local w, h = tonumber(object.width) or 0, tonumber(object.height) or 0
            local area = w * h
            if w > 0 and h > 0 and x >= ox and x <= ox+w and y >= oy and y <= oy+h
                and (not best_area or area < best_area
                    or (area == best_area and (tonumber(object.id) or 0) < (tonumber(best.id) or 0))) then
                best, best_area = object, area
            end
        end
    end
    if best then return M.id(room, best) end
    return nil, "Object " .. tostring(spawn.id) .. " is outside every Encounter or has an invalid Encounter link."
end

return M
