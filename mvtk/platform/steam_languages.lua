-- Shared Steamworks language data for schema checks and editor file generation.
-- Pure data: safe to require at startup, without project reads or Steam access.
-- API codes follow https://partner.steamgames.com/doc/store/localization/languages.
local M = {}
M.built_in = {
    en="english", de="german", fr="french", es="spanish", ["es-419"]="latam",
    it="italian", ja="japanese", ko="koreana", pt="portuguese", ["pt-BR"]="brazilian",
    ru="russian", ["zh-CN"]="schinese", ["zh-Hans"]="schinese",
    ["zh-TW"]="tchinese", ["zh-Hant"]="tchinese", pl="polish", nl="dutch",
    sv="swedish", da="danish", fi="finnish", no="norwegian", nb="norwegian",
    tr="turkish", uk="ukrainian", cs="czech", hu="hungarian", ro="romanian",
    el="greek", bg="bulgarian", th="thai", vi="vietnamese", id="indonesian",
    ms="malay", ar="arabic",
}
-- Derive the accepted values from the same map; never maintain a second list.
M.api_codes = {}
for _, code in pairs(M.built_in) do M.api_codes[code] = true end
return M
