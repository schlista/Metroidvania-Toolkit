-- Prepare both UI fonts from the text that can ship, using fresh disk configs.
-- The editor can rewrite protobuf escapes/defaults; compare decoded fields.
local Cmap = require "mvtk.editor.ttf_cmap"
local Resource = require "mvtk.editor.resource_text"
local Fresh = require "mvtk.editor.fresh_config"
local Transaction = require "mvtk.editor.project_transaction"
local Collector = require "developer.tools.localization_collect"
local Text = require "mvtk.ui.generated_text"
local Labels = require "mvtk.editor.ui_font_resources"
local Manifest = require "mvtk.editor.ui_font_manifest"
local M = {}
M.default_face = "developer/assets/fonts/DejaVuSansMono-Bold.ttf"
M.resources = {"assets/fonts/ui_text.font", "assets/fonts/ui_label.font"}

-- Decode strict UTF-8 as bytes: the editor host has no utf8 library.
function M.codepoints(text)
    assert(type(text) == "string", "Font source must be text")
    local points, i = {}, 1
    while i <= #text do
        local a, count, value = text:byte(i), 0, 0
        if a < 128 then count,value = 1,a
        elseif a >= 194 and a <= 223 then count,value = 2,a-192
        elseif a >= 224 and a <= 239 then count,value = 3,a-224
        elseif a >= 240 and a <= 244 then count,value = 4,a-240 end
        assert(count > 0 and i+count-1 <= #text, "Invalid UTF-8 font source at byte " .. i)
        for j=i+1,i+count-1 do
            local b = text:byte(j)
            assert(b >= 128 and b <= 191, "Invalid UTF-8 font source at byte " .. j)
            value = value*64+b-128
        end
        assert((count == 1 or value >= (count == 2 and 128 or count == 3 and 2048 or 65536))
            and value <= 0x10ffff and not (value >= 0xd800 and value <= 0xdfff), "Invalid Unicode font source")
        -- Line/tab controls affect layout, they have no drawable glyph.
        if value >= 32 and value ~= 127 then points[#points+1] = {code=value,text=text:sub(i,i+count-1)} end
        i = i+count
    end
    return points
end

function M.characters(texts)
    local set = {}
    for cp=32,126 do set[cp] = string.char(cp) end
    for _, text in ipairs(texts) do
        for _, point in ipairs(M.codepoints(text)) do set[point.code] = point.text end
    end
    local keys, out = {}, {}
    for cp in pairs(set) do keys[#keys+1] = cp end
    table.sort(keys)
    for _, cp in ipairs(keys) do out[#out+1] = set[cp] end
    return table.concat(out), keys
end

function M.escape(text)
    return (text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("'", "\\'"))
end

function M.valid_path(value)
    return require("mvtk.core.creator_settings_model").fields.ui_font_file.check(value)
end

local function strings(value, out)
    if type(value) == "string" then out[#out+1] = value
    elseif type(value) == "table" then for _, child in pairs(value) do strings(child,out) end end
end

local function material(label, mode)
    return "/builtins/fonts/" .. (label and "label-" or "font-") .. (mode=="vector" and "vector" or "df") .. ".material"
end
local function font_text(face, characters, label, mode, generation)
    local fields = 'font: "/' .. M.escape(face) .. '"\nmaterial: "' .. material(label,mode) .. '"\n'
    if mode=="vector" then
        -- res_font.cpp (1.14.1) refuses a Vector font with size 0, and the size sets the outline and
        -- shadow bitmaps. It does not change what resource.get_text_metrics measures (16 px, see
        -- mvtk/ui/generated_text.lua); the text nodes' Font Size 14 sets the drawn size.
        fields=fields..'size: '..Text.SIZE..'\nvector_font_mode: VECTOR_FONT_MODE_VECTOR\n'
    elseif generation=="dynamic" then
        fields=fields..'size: '..Text.SIZE..'\nvector_font_mode: VECTOR_FONT_MODE_SDF\n'
    else fields=fields..'size: '..Text.SIZE..'\noutput_format: TYPE_DISTANCE_FIELD\n' end
    if generation=="dynamic" then fields=fields..'runtime: true\n' end
    return fields..'characters: "'..M.escape(characters)..'"\n'
end
local function equivalent(old, face, characters, label, mode, generation)
    if not old then return false end
    local ok,doc=pcall(Resource.parse,old);if not ok then return false end
    local r=doc.root
    local function value(key,default)local v=Resource.value(r,key);if v==nil then return default end;return v end
    local vector=value("vector_font_mode","VECTOR_FONT_MODE_BITMAP")
    if vector~="VECTOR_FONT_MODE_BITMAP" and vector~="VECTOR_FONT_MODE_SDF" and vector~="VECTOR_FONT_MODE_VECTOR"then return false end
    local effective=vector=="VECTOR_FONT_MODE_BITMAP" and (value("output_format","TYPE_BITMAP")=="TYPE_DISTANCE_FIELD" and "distance_field" or "bitmap")
        or (vector=="VECTOR_FONT_MODE_VECTOR" and "vector" or "distance_field")
    if effective~=mode or value("runtime","false")~=(generation=="dynamic" and "true" or "false")then return false end
    if value("size",0)~=Text.SIZE then return false end
    for key,default in pairs({antialias=1,alpha=1,outline_alpha=0,outline_width=0,shadow_alpha=0,shadow_blur=0,
        shadow_x=0,shadow_y=0,extra_characters="",cache_width=0,cache_height=0,all_chars="false",render_mode="MODE_SINGLE_LAYER"})do
        if value(key,default)~=default then return false end
    end
    return value("characters","")==characters and value("font","")=="/"..face
        and value("material","")==material(label,mode) and #Resource.all(r,"styles")==0
end
local function settings(opts)
    local root=opts.root or "."
    local read=opts.read or Transaction.read
    local loader=Fresh.new{root=root,read=read}
    local registry=assert(loader.load_path("developer/config/localization.lua"))
    local creator=read(root.."/developer/config/creator_settings.lua") and assert(loader.load_path("developer/config/creator_settings.lua"))
    local overrides=creator and creator.published and creator.overrides and creator.overrides.localization or {}
    local mode=overrides.ui_text_rendering or registry.ui_text_rendering or "vector"
    local generation=overrides.ui_glyph_generation or registry.ui_glyph_generation or "static"
    assert(mode=="distance_field" or mode=="vector","Text rendering must be Distance field or Vector")
    assert(generation=="static" or generation=="dynamic","Glyph generation must be Built with the game or On demand")
    return mode,generation,overrides.ui_font_file or registry.ui_font_file or M.default_face
end
-- Native verification may establish an additional rule for static Vector.
-- Claude settles this hook with a real 1.14.1 build; do not infer it from Bob.
M.vector_static_needs_full_layout = false
local function project_files(opts,mode,generation)
    local files=Labels.plan(opts,mode)
    if generation=="dynamic" or (mode=="vector" and M.vector_static_needs_full_layout)then
        for _,file in ipairs(Manifest.plan(opts.root or ".",opts.read or Transaction.read))do files[#files+1]=file end
    end
    return files
end
-- Run before the room-generation snapshot so copied labels get this material.
function M.prepare(opts)
    opts=opts or {};local root=opts.root or "."
    Transaction.recover(root,opts.transaction)
    local mode,generation=settings(opts)
    return Transaction.commit(root,project_files(opts,mode,generation),opts.transaction)
end

local function build(opts)
    opts = opts or {}
    local root = (opts.root or "."):gsub("\\","/"):gsub("/$", "")
    Transaction.recover(root .. "/developer",opts.transaction)
    Transaction.recover(root,opts.transaction)
    local read = opts.read or Transaction.read
    local loader = Fresh.new({root=root,read=read})
    local registry = assert(loader.load_path("developer/config/localization.lua"))
    local mode,generation,face = settings(opts)
    assert(M.valid_path(face))
    local font = assert(Cmap.read(root .. "/" .. face, opts.read_binary))
    local entries = assert((opts.collect or Collector.collect)(opts))
    local english, texts, languages = {}, {}, {}
    strings(assert(loader.load_path("developer/config/ui_text.lua")),english)
    for _, entry in ipairs(entries) do english[#english+1] = entry.source end
    -- Include endonyms too: the player language selector displays these verbatim.
    local manifest = assert(loader.load_path("developer/config/translations/manifest_generated.lua"))
    local records = {}
    for _, language in ipairs(registry.languages) do records[language.code] = language end
    languages[#languages+1] = {code="en",name=records.en and records.en.name or "English",texts=english}
    for _, language in ipairs(registry.languages) do
        texts[#texts+1] = language.name
        if language.code == "en" then english[#english+1] = language.name end
    end
    local codes = {}
    for code, enabled in pairs(manifest) do
        if enabled then
            assert(type(code) == "string" and code:match("^[a-z][a-z0-9_-]*$"), "Invalid translation manifest code")
            codes[#codes+1] = code
        end
    end
    table.sort(codes)
    for _, code in ipairs(codes) do
        local values = {}
        strings(assert(loader.load_path("developer/config/translations/" .. code .. ".lua")), values)
        values[#values+1] = records[code] and records[code].name or code
        languages[#languages+1] = {code=code,name=records[code] and records[code].name or code,texts=values}
    end
    -- Registry-only languages still display their own name before any Import.
    for _, language in ipairs(registry.languages) do
        if language.code ~= "en" and not manifest[language.code] then
            languages[#languages+1] = {code=language.code,name=language.name,texts={language.name}}
        end
    end
    local report = {errors=0,lines={},changed={}}
    for _, language in ipairs(languages) do
        local missing = {}
        table.sort(language.texts)
        for _, text in ipairs(language.texts) do
            texts[#texts+1] = text
            for _, point in ipairs(M.codepoints(text)) do
                if not font.has(point.code) and not missing[point.code] then missing[point.code] = text end
            end
        end
        -- Even an empty game must support printable ASCII used by numeric/token output.
        if language.code == "en" then
            for cp=32,126 do if not font.has(cp) and not missing[cp] then missing[cp] = string.char(cp) end end
        end
        local points = {}
        for cp in pairs(missing) do points[#points+1] = cp end
        table.sort(points)
        for _, cp in ipairs(points) do
            report.errors = report.errors+1
            report.lines[#report.lines+1] = language.name .. " (" .. language.code .. "): missing U+"
                .. string.format("%04X",cp) .. ' in "' .. missing[cp] .. '"; choose a UI font file containing this letter.'
        end
    end
    if report.errors > 0 then return report end
    local characters, points = M.characters(texts)
    local files = project_files(opts,mode,generation)
    for i, path in ipairs(M.resources) do
        if not equivalent(read(root .. "/developer/" .. path),face,characters,i == 2,mode,generation) then
            files[#files+1] = {path="developer/"..path,content=font_text(face,characters,i == 2,mode,generation)}
        end
    end
    report.changed = Transaction.commit(root,files,opts.transaction)
    report.characters = characters
    report.lines[1] = string.format("UI font: %d characters, %d resources changed.",#points,#report.changed)
    if mode=="vector" then report.lines[#report.lines+1]="Vector text needs RGBA16F and R32UI textures; OpenGL ES 2 and WebGL 1 devices cannot draw it. Exclude GLES 2.0 when bundling, or choose Distance field for those devices." end
    if generation=="dynamic" then report.lines[#report.lines+1]="On demand bundles the font file and uses full text layout; refresh the native engine after changing the manifest." end
    for _,path in ipairs(report.changed)do report.lines[#report.lines+1]="Updated "..path end
    return report
end

function M.build(opts)
    local ok, result = pcall(build,opts)
    if not ok then return nil, tostring(result) end
    return result
end

return M
