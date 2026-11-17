-- Room-derived outputs share one scan and the room baker's normalization rules.
-- Producers load during editor boot: defer context-dependent builders to render.
local PropertyFlattener = require "mvtk.tiled.property_flattener"
local EnemyOverrides = require "mvtk.enemies.enemy_overrides"
local M = {}

M.PRODUCERS = {
    require "mvtk.editor.room_catalogs.cutscenes",
    require "mvtk.editor.room_catalogs.world_census",
}

function M.empty_files()
    local files = {}
    for _, producer in ipairs(M.PRODUCERS) do
        files[#files + 1] = { path=producer.path, content=producer.render(producer.new_acc()) }
    end
    return files
end

local function accepts(producer, kind)
    if producer.types == "*" then return true end
    for _, name in ipairs(producer.types) do
        if name == kind then return true end
    end
    return false
end

function M.write(ctx, room_ids)
    local accumulators = {}
    ctx.room_ids = room_ids
    local known_types = ctx.load_object_type_set()
    for i, producer in ipairs(M.PRODUCERS) do accumulators[i] = producer.new_acc() end
    for _, room_id in ipairs(room_ids) do
        local map = ctx.load_tiled_export(room_id)
        if map then
            local layers = ctx.flatten_tiled_layers(map.layers)
            for i, producer in ipairs(M.PRODUCERS) do
                if producer.collect_room then producer.collect_room(accumulators[i], ctx, room_id, map, layers) end
            end
            for _, entry in ipairs(layers) do
                local layer = entry.layer
                if entry.visible ~= false and layer and layer.type == "objectgroup" then
                    for _, raw in ipairs(layer.objects or {}) do
                        if raw and raw.visible ~= false then
                            local obj = {}
                            for key, value in pairs(raw) do obj[key] = value end
                            obj.properties = PropertyFlattener.flatten(raw.properties)
                            obj.x = (tonumber(raw.x) or 0) + (tonumber(entry.offsetx) or 0)
                            obj.y = (tonumber(raw.y) or 0) + (tonumber(entry.offsety) or 0)
                            local kind = ctx.resolve_object_type(obj, known_types)
                            if kind == "enemy" then obj.properties = EnemyOverrides.flatten_tiled_properties(raw.properties) end
                            if ctx.is_background_visual_object_candidate(obj, layer.name) then kind = "background_visual" end
                            obj.type = kind or obj.type
                            for i, producer in ipairs(M.PRODUCERS) do
                                if accepts(producer, kind) then
                                    producer.collect(accumulators[i], ctx, room_id, obj, obj.properties)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local result = { changed_files={} }
    for i, producer in ipairs(M.PRODUCERS) do
        local text, count = producer.render(accumulators[i], ctx)
        if text and ctx.write_if_changed(ctx.root .. "/" .. producer.path, text) then
            result.changed_files[#result.changed_files + 1] = producer.path
            ctx.info("[CATALOGS] Updated " .. producer.path .. " (" .. tostring(count or 0) .. " entries)")
        end
    end
    return result
end

return M
