-- Exact source-text translations and named UI wording. Shared runtime state.
local Util = require "mvtk.core.util"
local Config = require("developer.config.runtime_settings").section("localization",
    Util.require_config("developer.config.localization"))
local English = Util.require_config("developer.config.ui_text")
-- Localization can load before the boot config gate registers build_deps.
-- Keep the generated language tables in every localization host's closure.
if false then require "developer.config.translations.manifest_generated" end
local Manifest = Util.require_config("developer.config.translations.manifest_generated")
local M = {}
local registry, tables = {}, {}
for _, entry in ipairs(Config.languages) do registry[entry.code] = entry end
local current = Config.fallback
local revision = 0
-- Diagnostic rendering state is session-only, never a language or preference.
local pseudo = false

-- Blank text stays blank, so empty labels and nodes keep their meaning.
local function bracket(text)
    return pseudo and text ~= "" and ("[" .. text .. "]") or text
end

local function supported(code)
    return type(code) == "string" and registry[code] and code or nil
end

local function translations(code)
    if not tables[code] then
        -- An absent table is normal (the shipped English-only registry has none).
        tables[code] = Manifest[code] and Util.require_config("developer.config.translations." .. code) or {}
    end
    return tables[code]
end

local function lookup(code, key)
    local value = translations(code)[key]
    -- Entries are flat text; anything else would reach gui.set_text as a table.
    if type(value) == "string" and value ~= "" then return value end
end

function M.tr(source)
    source = tostring(source or "")
    local text = lookup(current, source) or lookup(Config.fallback, source) or source
    return bracket(text)
end

function M.ui(key)
    local text = lookup(current, key) or lookup(Config.fallback, key) or English[key] or key
    return bracket(text)
end

-- Only named placeholders are filled: input tokens and unknown params survive.
function M.format(template, params)
    local text = tostring(template or ""):gsub("{([%w_]+)}", function(name)
        local value = params and params[name]
        if value ~= nil then return tostring(value) end
        return "{" .. name .. "}"
    end)
    return text
end

-- Picks the current language's form without translating it, so forms may be
-- ui_text keys. one_few_many uses the Slavic integer rule; fractions use other
-- when supplied, otherwise many. Negative counts use abs.
function M.plural_form(forms, n)
    local rule = registry[current].plural
    local count, category = math.abs(tonumber(n) or 0), "other"
    if rule == "one_other" then
        if count == 1 then category = "one" end
    elseif rule == "one_few_many" then
        local last, last_two = count % 10, count % 100
        if count % 1 ~= 0 then category = forms.other and "other" or "many"
        elseif last == 1 and last_two ~= 11 then category = "one"
        elseif last >= 2 and last <= 4 and (last_two < 12 or last_two > 14) then category = "few"
        else category = "many" end
    end
    return forms[category] or forms.other or forms.one or ""
end

-- Forms contain source strings; the chosen one is translated.
function M.plural(forms, n)
    return M.tr(M.plural_form(forms, n))
end

function M.set_language(code)
    if code == "auto" then
        local info = sys.get_sys_info()
        code = info and info.language
    end
    code = supported(code) or supported(Config.default_language) or Config.fallback
    if code ~= current then current = code; revision = revision + 1 end
    return current
end

function M.language() return current end
function M.languages()
    local out = {}
    for i, entry in ipairs(Config.languages) do
        out[i] = { code = entry.code, name = entry.name, plural = entry.plural }
    end
    return out
end
function M.show_language_choice() return Config.show_language_choice ~= false and #Config.languages > 1 end
function M.revision() return revision end

-- Only the debug Dev Menu calls this; release builds and disabled tools refuse it.
-- The registry stays untouched, including the one-language row visibility rule.
function M.set_pseudo(enabled)
    local allowed = false
    if sys and sys.get_engine_info then
        local ok, info = pcall(sys.get_engine_info)
        if ok and info and info.is_debug == true then
            local debug = Util.require_config("developer.config.debug_config")
            allowed = debug.dev_tools and debug.dev_tools.enabled == true
        end
    end
    local next_value = enabled == true and allowed == true
    if pseudo ~= next_value then pseudo = next_value; revision = revision + 1 end
    return pseudo
end
function M.pseudo() return pseudo end

-- Compatibility for old keyed callers; new creator text always uses tr().
function M.t(key)
    if type(key) == "string" and key:sub(1, 3) == "ui." then
        local value = M.ui(key:sub(4))
        return value ~= key:sub(4) and value or key
    end
    return English[key] and M.ui(key) or M.tr(key)
end
M.set_locale = M.set_language
M.get_locale = M.language
return M
