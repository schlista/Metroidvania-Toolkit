-- Optional Steam bridge; its state lasts for this Lua process, across save slots.
-- API signatures: https://raw.githubusercontent.com/defold/extension-steam/1.15.0/steam/api/steam.script_api
-- Lifecycle/platform guard: same tag, steam/src/steam.cpp; listener ownership:
-- steam/src/steam_listener.cpp; achievement/store returns: steam/src/steam_userstats.cpp.
-- Presence boolean writes and clear: extension-steam 1.15.0,
-- steam/src/steam_friends.cpp:300-321 (only after successful init).
local M = {}
local attempted, active = false, false
local api, names
local sent, pending = {}, {}
local dirty, elapsed = false, 0
local presence_sent
-- Coalesce all unlocks into one store per five seconds, including failed retries.
local STORE_INTERVAL = 5
local function sandboxed()
    return require("mvtk.core.checkpoint").is_save_sandboxed()
end
local function listener(self, event, data)
    -- Consume callbacks on the persistent boot script. Stored callbacks contain
    -- placeholder data in 1.15.0; they cannot confirm server persistence.
end
function M.init()
    if attempted then return end
    attempted = true
    -- The extension registers no module on unsupported platforms or while off.
    if type(steam) ~= "table" then return end
    api = steam
    -- init() takes no app id: Steam launch / steam_appid.txt supplies it.
    local ok, err = api.init()
    if not ok then
        print("[STEAM] Disabled: " .. tostring(err))
        return
    end
    names = require("developer.config.steam_settings").achievement_names
    -- Called through PlatformServices.init from the app-lifetime boot script.
    api.set_listener(listener)
    active = true
end
local function send(id)
    if api.user_stats_set_achievement(names[id] or id) then
        sent[id], pending[id], dirty = true, nil, true
    else
        pending[id] = true
    end
end
function M.unlock_achievement(id)
    if not active or sandboxed() or type(id) ~= "string" or id == "" then return end
    if not sent[id] and not pending[id] then send(id) end
end
function M.sync_achievements(ids)
    if not active or sandboxed() then return end
    -- sent/pending also deduplicate fresh unlocks and repeated slot starts.
    for _, id in ipairs(ids or {}) do M.unlock_achievement(id) end
end
function M.set_rich_presence(state, region_id)
    if not active then return end
    local settings = require("developer.config.steam_settings").rich_presence
    if type(settings) ~= "table" or settings.enabled ~= true then return end
    local Tokens = require "mvtk.platform.rich_presence_tokens"
    if not Tokens.TOKENS[state] then return end
    if state == "region" and not Tokens.region_ok(region_id, region_id) then state = "playing" end
    region_id = state == "region" and region_id or ""
    if presence_sent == state .. region_id then return end
    -- Any attempted change can partially alter Steam's state. Invalidate the
    -- old cache as well, so returning to it after a failed write retries.
    presence_sent = nil
    local region_written = api.friends_set_rich_presence(Tokens.REGION_KEY, region_id)
    if not region_written and state == "region" then
        state, region_id = "playing", ""
        region_written = api.friends_set_rich_presence(Tokens.REGION_KEY, "")
    end
    local display_written = api.friends_set_rich_presence("steam_display", Tokens.TOKENS[state])
    if region_written and display_written then presence_sent = state .. region_id end
end
function M.update(dt)
    if not active then return end
    -- update() takes no dt. Pump callbacks every frame, on the title screen and in a
    -- sandbox too; a sandbox only holds back achievement sends and stores.
    api.update()
    if sandboxed() then return end
    elapsed = elapsed + dt
    if elapsed < STORE_INTERVAL then return end
    elapsed = 0
    local ids = {}
    for id in pairs(pending) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do send(id) end
    if dirty and api.user_stats_store_stats() then dirty = false end
end
function M.final()
    if not active then return end
    active = false
    -- Do not bypass the store rate limit at shutdown. Durable profile unlocks
    -- are re-sent next process, including a last batch not yet stored here.
    api.friends_clear_rich_presence()
    api.final()
end
return M
