-- Shared by the runtime and Steamworks localization generator; pure data/rules.
local M = {}
M.TOKENS = { title = "#Status_Title", playing = "#Status_Playing", region = "#Status_Region" }
M.REGION_KEY = "region"

function M.region_ok(id, name)
    return type(id) == "string" and #id < 256 and id:match("^[%w_]+$") ~= nil
        and type(name) == "string" and name:match("%S") ~= nil
end

function M.region_token(id)
    return "#Region_" .. id
end

return M
