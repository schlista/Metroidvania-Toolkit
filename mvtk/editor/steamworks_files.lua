-- Steam Auto-Cloud owns synchronization: never call remote_storage_* here.
-- Extension-steam 1.15.0 truncates reads at NUL and exposes no file delete,
-- exists or timestamp API, so it cannot safely mirror binary saves.
-- Pure editor text generation; callers supply fresh project reads and writes.
local Fresh = require "mvtk.editor.fresh_config"
local Languages = require "mvtk.platform.steam_languages"
local Tokens = require "mvtk.platform.rich_presence_tokens"
local Addon = require "mvtk.editor.steam_addon"
local M = {}
M.DIRECTORY = "developer/addons/steam/steamworks"

local function context(opts)
    local root = tostring(opts.root or "."):gsub("\\", "/"):gsub("/$", "")
    local read = assert(opts.read, "Steamworks generation needs a project reader")
    local loader = Fresh.new({root=root, read=read})
    local function config(path)
        if read(root .. "/" .. path) == nil then return {} end
        local value, err = loader.load_path(path)
        assert(value, err)
        return value
    end
    return config, root, read
end

function M.enabled(opts)
    local config, root, read = context(opts)
    if Addon.state({["game.project"]=read(root .. "/game.project")}) ~= "on" then return false end
    local settings = config("developer/config/steam_settings.lua")
    return (settings.rich_presence or {}).enabled == true or (settings.cloud_saves or {}).enabled == true
end

-- Match SavePaths.for_identity without runtime config/sys or LuaJ hex formats.
function M.save_folder(identity)
    identity = tostring(identity)
    local checksum = 0
    for i = 1, #identity do checksum = (checksum * 131 + identity:byte(i)) % 2147483647 end
    local digits, hex = "0123456789abcdef", ""
    for _ = 1, 8 do
        local digit = checksum % 16
        hex = digits:sub(digit + 1, digit + 1) .. hex
        checksum = math.floor(checksum / 16)
    end
    return "mvtk_" .. identity:lower():gsub("[^a-z0-9_-]", "_"):sub(1, 48) .. "_" .. hex
end

function M.auto_cloud_text(settings, game_id, max_slots)
    assert(type(game_id) == "string" and game_id:match("%S"),
        "Steam Cloud needs a nonblank game_id in developer/config/persistence_settings.lua; save the game's identity before preparing.")
    local cloud = settings.cloud_saves or {}
    max_slots = tonumber(max_slots) or 3
    local folder = M.save_folder(game_id)
    local patterns = {"mvtk_save_slot_*", "mvtk_last_slot", "mvtk_profile*"}
    if cloud.include_preferences == true then patterns[#patterns + 1] = "mvtk_settings" end
    if cloud.include_controls == true then patterns[#patterns + 1] = "mvtk_bindings_v2" end
    local files = 4 * max_slots + 3 + (#patterns - 3)
    local lines = {"Steamworks > Steam Cloud", "Auto-Cloud syncs only when Steam starts the game",
        "Editor runs with steam_appid.txt never sync. Sync occurs at Steam launch and exit.", "",
        "Root | Subdirectory | Pattern | OS | Recursive"}
    for _, pattern in ipairs(patterns) do
        lines[#lines + 1] = "WinAppDataRoaming | " .. folder .. " | " .. pattern .. " | [Cross-Platform] | off"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Root Overrides (keep [Cross-Platform] on every row and the same subdirectory):"
    lines[#lines + 1] = "WinAppDataRoaming -> MacAppSupport | macOS | " .. folder .. " | experimental"
    lines[#lines + 1] = "WinAppDataRoaming -> LinuxXdgDataHome | Linux | " .. folder .. " | experimental; Linux path UNVERIFIED"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Quota advice: 4 x %d slots + 3 files + %d optional includes.", max_slots, #patterns - 3)
    lines[#lines + 1] = string.format("Number of files allowed per user: %d", files)
    lines[#lines + 1] = string.format("Byte quota per user: at most %d bytes (%d KB; files x 512 KB upper bound).", files * 512 * 1024, files * 512)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "1. Enter every row and Root Override in Steamworks > Steam Cloud."
    lines[#lines + 1] = "2. Set Byte quota per user and Number of files allowed per user."
    lines[#lines + 1] = "3. Click Save."
    lines[#lines + 1] = "4. Publish the changes."
    lines[#lines + 1] = "5. Upload a build for your own app ID."
    lines[#lines + 1] = "6. In the Steam console run testappcloudpaths <AppId>."
    lines[#lines + 1] = "7. Run set_spew_level 4 4."
    lines[#lines + 1] = "8. Launch the uploaded build from the Steam client."
    lines[#lines + 1] = "9. Inspect %Steam Install%/logs/cloud_log.txt."
    lines[#lines + 1] = "10. Test save, deletion and offline conflicts on two machines; neither app 480 nor the editor verifies Cloud."
    return table.concat(lines, "\n") .. "\n"
end

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end
local function escape(text)
    return text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
end
local function checked(text, region)
    if type(text) ~= "string" or not text:match("%S") then return nil end
    local rest, count = text, 0
    if region then rest, count = text:gsub("{region}", "") end
    if (region and count ~= 1) or rest:find("[%%{}]") then return nil end
    if region then return (text:gsub("{region}", "{#Region_%%region%%}")) end
    return text
end

function M.rich_presence_vdf(opts)
    local config = context(opts)
    local settings = opts.settings or config("developer/config/steam_settings.lua")
    local registry = config("developer/config/localization.lua")
    local biomes = config("developer/config/biomes.lua")
    local presence = settings.rich_presence or {}
    local warnings, blocks, tables, codes = {}, {}, {}, {}
    for _, language in ipairs(registry.languages or {}) do codes[language.code] = true end
    local function translations(code)
        if not code then return {} end
        -- Codes are filenames, not paths. The language registry validator owns
        -- the full code rules; refuse traversal even in direct generator calls.
        assert(type(code) == "string" and code:match("^[%w_-]+$"), "Invalid Steamworks language code")
        if not tables[code] then tables[code] = config("developer/config/translations/" .. code .. ".lua") end
        return tables[code]
    end
    local fallback = translations(registry.fallback)
    local regions = {}
    for _, id in ipairs(sorted_keys(biomes)) do
        local name = type(biomes[id]) == "table" and biomes[id].name
        if type(name) == "string" and name:match("%S") then
            if Tokens.region_ok(id, name) then regions[id] = name
            else warnings[#warnings + 1] = "Steam rich presence skips named biome id '" .. tostring(id) .. "': it fails region_ok." end
        end
    end
    local function block(code)
        local values, out = translations(code), {}
        local function add(key, source, region)
            local text = values[source]
            if type(text) ~= "string" or text == "" then text = fallback[source] end
            if type(text) ~= "string" or text == "" then text = source end
            local accepted = checked(text, region)
            if accepted then out[key] = accepted
            else warnings[#warnings + 1] = "Steam rich presence skips " .. key .. " in " .. tostring(code)
                .. ": rejected text (%, { or } outside the single {region} placeholder, or blank text)." end
        end
        add(Tokens.TOKENS.title, presence.title, false)
        add(Tokens.TOKENS.playing, presence.playing, false)
        add(Tokens.TOKENS.region, presence.region, true)
        for _, id in ipairs(sorted_keys(regions)) do add(Tokens.region_token(id), regions[id], false) end
        return out
    end
    -- English is Steam's fallback, regardless of the game's fallback setting.
    if codes.en then blocks.english = block("en")
    else
        warnings[#warnings + 1] = "Steam rich presence has no en language; english uses fallback language '" .. tostring(registry.fallback) .. "'."
        blocks.english = block(registry.fallback)
    end
    for _, code in ipairs(sorted_keys(codes)) do
        local steam_code = (settings.steam_languages or {})[code] or Languages.built_in[code]
        if not steam_code or not Languages.api_codes[steam_code] then
            warnings[#warnings + 1] = "Steam rich presence has no Steam language mapping for '" .. code .. "'; skipped."
        elseif code ~= "en" and steam_code ~= "english" then
            -- Aliases map to one Steam language; sorted first code wins.
            if not blocks[steam_code] then blocks[steam_code] = block(code) end
        end
    end
    local lines = {'"lang"', '{'}
    for _, code in ipairs(sorted_keys(blocks)) do
        lines[#lines + 1] = '\t"' .. code .. '"'
        lines[#lines + 1] = '\t{'
        lines[#lines + 1] = '\t\t"tokens"'
        lines[#lines + 1] = '\t\t{'
        for _, key in ipairs(sorted_keys(blocks[code])) do
            lines[#lines + 1] = '\t\t\t"' .. key .. '"\t\t"' .. escape(blocks[code][key]) .. '"'
        end
        lines[#lines + 1] = '\t\t}'
        lines[#lines + 1] = '\t}'
    end
    lines[#lines + 1] = '}'
    return table.concat(lines, "\n") .. "\n", warnings
end

function M.files(opts)
    if not M.enabled(opts) then return {} end
    local config = context(opts)
    local settings = config("developer/config/steam_settings.lua")
    local files = {}
    if (settings.rich_presence or {}).enabled == true then
        files[#files + 1] = {path=M.DIRECTORY .. "/rich_presence.vdf", content=M.rich_presence_vdf(opts)}
    end
    if (settings.cloud_saves or {}).enabled == true then
        local game = config("developer/config/game_config.lua")
        local saves = (game.progression or {}).saves or {}
        files[#files + 1] = {path=M.DIRECTORY .. "/auto_cloud.txt",
            content=M.auto_cloud_text(settings, config("developer/config/persistence_settings.lua").game_id, saves.max_slots)}
    end
    return files
end

return M
