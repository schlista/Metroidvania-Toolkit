-- Pure clip selection and authoring diagnostics, shared by runtime and LuaJ tooling.
local M = {}

local function nonblank(value)
    return type(value) == "string" and value:match("%S") and value or nil
end

local function uri(entry, editor)
    return (editor and nonblank(entry.editor_uri)) or nonblank(entry.uri)
end

function M.resolve(spec, step, ctx)
    spec, step, ctx = spec or {}, step or {}, ctx or {}
    local selected = spec
    if nonblank(step.uri) or nonblank(step.editor_uri) then
        selected = step
    else
        local variants = type(spec.variants) == "table" and spec.variants or {}
        local language = ctx.language or ""
        local keys = {}
        if ctx.captions then keys[#keys + 1] = language .. "_subtitled" end
        keys[#keys + 1] = language
        if ctx.captions then keys[#keys + 1] = "subtitled" end
        for _, key in ipairs(keys) do
            local entry = variants[key]
            if type(entry) == "table" and uri(entry, ctx.editor) then selected = entry; break end
        end
    end
    local play_sound = step.play_sound
    if play_sound == nil then play_sound = selected.play_sound end
    if play_sound == nil then play_sound = spec.play_sound end
    local timeout = tonumber(step.timeout or selected.timeout or spec.timeout) or 20.0
    return {uri = uri(selected, ctx.editor), play_sound = play_sound == true, timeout = math.max(0, timeout)}
end

local function sorted_keys(value)
    local out = {}; for key in pairs(value) do out[#out + 1] = key end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

local function packaged_editor_uri(path)
    local folder = path:match("^developer/assets/cutscenes/([^/]+)/.+")
    local platforms = {common=true,ios=true,android=true,osx=true,win32=true,linux=true,web=true,switch=true}
    local platform = folder and folder:match("^[%w_]+%-(%w+)$")
    return folder and (platforms[folder] or (platform ~= "common" and platforms[platform]))
end

function M.validate(videos, languages)
    local warnings, allowed = {}, {subtitled = true}
    for _, language in ipairs(languages or {}) do
        local code = type(language) == "table" and language.code or language
        if type(code) == "string" then allowed[code], allowed[code .. "_subtitled"] = true, true end
    end
    for _, id in ipairs(sorted_keys(videos or {})) do
        local spec = videos[id]
        local variants = type(spec) == "table" and type(spec.variants) == "table" and spec.variants or {}
        for _, key in ipairs(sorted_keys(variants)) do
            local entry = type(variants[key]) == "table" and variants[key] or {}
            local property = tostring(id) .. ".variants." .. tostring(key)
            if not allowed[key] then
                warnings[#warnings + 1] = {code="video_variant_key", property=property,
                    message="Unknown video variant '" .. tostring(key) .. "'.",
                    fix="Use subtitled, a configured language code, or a language code followed by _subtitled."}
            end
            if not nonblank(entry.uri) and not nonblank(entry.editor_uri) then
                warnings[#warnings + 1] = {code="video_variant_uri", property=property,
                    message="Video variant has no uri or editor_uri.", fix="Add a playback path or remove this variant."}
            end
            if nonblank(entry.editor_uri) and not packaged_editor_uri(entry.editor_uri) then
                warnings[#warnings + 1] = {code="video_variant_editor_uri", property=property .. ".editor_uri",
                    message="Video variant editor_uri is outside a bundled resource subfolder.",
                    fix="Place the clip under developer/assets/cutscenes/common/ or a platform folder."}
            end
        end
    end
    return warnings
end

return M
