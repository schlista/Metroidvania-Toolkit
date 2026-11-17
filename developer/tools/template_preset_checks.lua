-- Editor-English diagnostics for placed template presets. No engine or IO calls.
local Presets = require "mvtk.tiled.template_presets"
local M = {}

function M.validate(index, cfg, issue)
    local usage = {}
    for _, object in ipairs((index or {}).objects or {}) do
        if object.visible ~= false and object.top_level ~= false then
            local props = object.properties or {}
            local value = props.mvtk_preset_of
            if value ~= nil and value ~= "" then
                local base = Presets.base(value)
                if not base then
                    issue("error", "preset_unknown_base", object, "mvtk_preset_of",
                        "Template preset names an unknown base '" .. tostring(value) .. "'.",
                        "Select a curated base and save the template preset again.")
                else
                    if object.type ~= base.type then
                        issue("error", "preset_type_mismatch", object, "mvtk_preset_of",
                            "Template preset resolves as '" .. tostring(object.type) .. "' but its base is '" .. base.type .. "'.",
                            "Clear the placed object's class override or choose a preset with that base type.")
                    end
                    if props.mvtk_template_version ~= base.version then
                        issue("warning", "preset_base_changed", object, "mvtk_template_version",
                            "Template preset base '" .. tostring(value) .. "' is version " .. base.version
                                .. "; the placed preset records '" .. tostring(props.mvtk_template_version or "") .. "'.",
                            "Select a placed preset, choose Save as Template Preset... and update it")
                    end
                end
            end
            local preset = props.mvtk_preset
            if type(preset) == "string" and preset ~= "" then
                local row = usage[preset]
                if not row then
                    row = {object = object, rooms = {}, placements = 0}
                    usage[preset] = row
                end
                row.placements = row.placements + 1
                if object.room then row.rooms[object.room] = true end
            end
        end
    end
    local names = {}
    for name in pairs(usage) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local row, rooms = usage[name], 0
        for _ in pairs(row.rooms) do rooms = rooms + 1 end
        issue("info", "preset_usage", row.object, "mvtk_preset",
            "Template preset '" .. name .. "': " .. tostring(rooms) .. " rooms, "
                .. tostring(row.placements) .. " placements.", nil)
    end
end

return M
