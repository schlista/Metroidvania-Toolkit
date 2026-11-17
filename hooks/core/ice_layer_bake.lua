-- Optional painted ice tags share grapple's deterministic merged-run collector.
local Grapple = require "hooks.core.grapple_layer_bake"
local M = {}

function M.probe_margin()
    local config = require "developer.config.tiled_object_config"
    local ice = (config.surface_layers or {}).ice or {}
    return tonumber(ice.probe_margin_px) or 8
end

function M.append(C, rows, rid, map)
    local runs, cells = Grapple.collect(map, "ice", "Ice")
    local tw, th = tonumber(map.tilewidth) or 0, tonumber(map.tileheight) or tonumber(map.tilewidth) or 0
    local map_height = (tonumber(map.height) or 0) * th
    local margin, seen = M.probe_margin(), {}
    for _, run in ipairs(runs) do
        local id = Grapple.instance_id(run, "ice_layer")
        assert(not seen[id], "Duplicate ice strip coordinates: " .. id)
        seen[id] = true
        local obj = {x = run.x, y = run.y - margin, width = run.w, height = run.h + margin}
        local x, y, _, _, w, h = C.rect_center_and_scale(obj, map_height - obj.y, tw, th, 128, 16, 256, 32)
        local filename = tostring(rid) .. "_" .. id .. ".go"
        assert(C.write_sized_rect_generated_go(C.join(C.PATH.generated_go, filename),
            "/developer/game/prefabs/ice_floor.go", w, h, 128, 16, 256, 32))
        C.add_prefab_instance(rows, id, require("mvtk.editor.shared_proto").generated_dir(C) .. "/" .. filename, x, y, nil, nil, "script", {
            C.text_prop("preset", "ice", "ice"),
        })
    end
    if cells > 0 then C.info(string.format("[CREATE ROOMS] room %s: ice layer %d cells -> %d strips", tostring(rid), cells, #runs)) end
    return runs
end
return M
