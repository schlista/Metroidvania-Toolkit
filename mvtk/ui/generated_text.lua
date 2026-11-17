-- Shared nominal size for generated fonts and their authored clone templates.
-- Font Size is not exposed to Lua in 1.14.1; clones retain the authored value.
-- VECTOR_REFERENCE_SIZE: Defold 1.14.1 measures a Vector font at Bob's fixed reference size
-- (Fontc.java VECTOR_REFERENCE_SIZE = 16), whatever the .font size says, while GUI nodes draw it
-- at their Font Size (authored SIZE). A native run measured "Training Blade" at 134.25 px in
-- Vector against 117.5 px in Distance field, exactly 16/14, and the HUD cut its last letter.
local M = { SIZE = 14, TEMPLATE_ID = "generated_text_template", VECTOR_REFERENCE_SIZE = 16 }

-- Named in variables: the editor requires this module for SIZE and must not load runtime
-- settings. Both modules have literal requires elsewhere (mvtk/core/localization.lua, build_deps).
local SETTINGS_MODULE, LOCALIZATION_MODULE = "developer.config.runtime_settings", "developer.config.localization"
local measure_scale

-- 1 for Distance field; SIZE / VECTOR_REFERENCE_SIZE when Game Settings > Languages >
-- Text rendering is Vector (the same setting Prepare & Check writes the fonts from). The
-- mismatch is the engine's, so outside it (desktop tests and their metric stubs) the scale
-- stays 1 unless a test sets one.
function M.measure_scale()
    if measure_scale == nil then
        measure_scale = 1
        if type(sys) == "table" and type(sys.get_engine_info) == "function" then
            local ok, config = pcall(function()
                return require(SETTINGS_MODULE).section("localization", require(LOCALIZATION_MODULE))
            end)
            if ok and type(config) == "table" and config.ui_text_rendering == "vector" then
                measure_scale = M.SIZE / M.VECTOR_REFERENCE_SIZE
            end
        end
    end
    return measure_scale
end

-- Tests pin a scale; nil reads the setting again on the next measurement.
function M.set_measure_scale(scale) measure_scale = scale end

-- resource.get_text_metrics at the size generated text is drawn. Callers pass their own
-- `resource` (tests give each script its own stub, which this module cannot see). A wrap width is in
-- drawn pixels, so it is converted to the measured size first. Options are never passed as an
-- explicit nil.
function M.metrics(font, text, options, resources)
    resources = resources or resource
    local scale = M.measure_scale()
    if scale == 1 then
        if options == nil then return resources.get_text_metrics(font, text) end
        return resources.get_text_metrics(font, text, options)
    end
    local measured
    if type(options) == "table" then
        local copy = {}
        for key, value in pairs(options) do copy[key] = value end
        if type(copy.width) == "number" then copy.width = copy.width / scale end
        measured = resources.get_text_metrics(font, text, copy)
    else
        measured = resources.get_text_metrics(font, text)
    end
    return { width = (measured.width or 0) * scale, height = (measured.height or 0) * scale,
        max_ascent = (measured.max_ascent or 0) * scale, max_descent = (measured.max_descent or 0) * scale }
end

function M.new(api, scene, position, text)
    local ok, template = pcall(api.get_node, M.TEMPLATE_ID)
    assert(ok and template, "Missing generated text template in " .. scene .. ": " .. M.TEMPLATE_ID)
    -- The legacy constructor measures literal text with the scene's default
    -- font. resource.get_text_metrics parses markup and is not equivalent.
    -- The deleted probe never renders, but occupies a pool slot until cleanup.
    -- Scene budgets reserve these probes as well as live/previous draw nodes.
    local measurement = api.new_text_node(position, text)
    local size = api.get_size(measurement)
    api.delete_node(measurement)
    -- The constructor measures like resource.get_text_metrics, so Vector needs the same scale.
    local scale = M.measure_scale()
    if scale ~= 1 then
        local x, y = size.x * scale, size.y * scale
        size = vmath and vmath.vector3(x, y, size.z) or { x = x, y = y, z = size.z }
    end
    local node = api.clone(template)
    api.set_enabled(node, true)
    api.set_position(node, position)
    api.set_text(node, text)
    api.set_size(node, size)
    return node
end

return M
