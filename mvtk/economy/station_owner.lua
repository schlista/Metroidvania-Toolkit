-- Shared gameobject-side owner for placed stations and NPC vendors.
-- Call open(self, context), forward on_message, and call final(self) on removal.
-- Context supplies station identity, title, room, position and store selling properties.
-- The private snapshot, never the GUI echo, supplies the transaction context.
local M = {}
local next_session = 0

function M.open(self, context, interaction)
    if self._station_menu or require("mvtk.bosses.fight_lock").is_locked(context.room_id) then return false end
    local own, public = {}, {}
    for _, key in ipairs({"station_kind", "station_id", "catalog_id", "menu_title", "room_id", "bank_mode"}) do
        own[key], public[key] = context[key], context[key]
    end
    if context.station_kind == "offering_altar" then
        for _, key in ipairs(require("mvtk.economy.catalog").OFFER_FIELDS) do
            own[key], public[key] = context[key], context[key]
        end
    end
    own.buys_items = context.buys_items ~= false
    own.buys = own.buys_items -- Transaction.sell expects this field.
    local share = require("mvtk.economy.selling").share(context.sell_share,
        require("mvtk.economy.transaction").sell_settings(context).sell_share)
    -- Preserve invalid authored overrides so the transaction still refuses them.
    own.sell_share = share or context.sell_share
    public.buys_items, public.sell_share = own.buys_items, own.sell_share
    if context.position then
        own.position = { x = context.position.x, y = context.position.y }
        public.position = { x = context.position.x, y = context.position.y }
    end
    next_session = next_session + 1
    -- The GUI first reveals its token with a choice; this nonce also guards
    -- the first choice after reopening the same station.
    public.session_token = next_session
    self._station_menu = { context = own, session_token = next_session }
    msg.post("main:/list_menu_gui#list_menu", "open_list_menu", {
        screen = "trade_station", context = public, owner = msg.url(),
        interaction_result = interaction and interaction.interaction_result
            and require("mvtk.game.interaction_result").defer(interaction) or nil,
    })
    return true
end

local function purchase(context, entry_id)
    local Catalog = require "mvtk.economy.catalog"
    local entry = Catalog.entry(context, entry_id)
    local result = require("mvtk.economy.transaction").buy(context, entry_id)
    local sounds = (Catalog.config(context).settings or {}).sounds or {}
    if not result.ok then
        return result.message or { key = "list.action_failed" }, sounds.fail
    end
    if result.saved == false and (Catalog.config(context).settings or {}).autosave_after_purchase ~= false
        and not require("mvtk.core.checkpoint").is_save_suspended() then
        return { key = "shop.save_failed" }, sounds.fail, true
    end
    local name = entry.name and entry.name ~= "" and { text = entry.name }
        or require("mvtk.game.grants").describe(entry.gives)
    return { key = "shop.bought", params = { name = name } }, sounds.buy, true
end

local function offer(context, entry_id)
    local Catalog = require "mvtk.economy.catalog"
    local sounds = (Catalog.config(context).settings or {}).sounds or {}
    if entry_id ~= "offering" then return { key = "list.action_failed" }, sounds.fail end
    if Catalog.offering_used(context) then return { key = "altar.already_offered" }, sounds.fail end
    context.instance_id = "altar:" .. context.station_id
    context.source, context.reason = "offering", "offering"
    context.set_flags = { ["altar_used:" .. context.station_id] = true }
    local result = require("mvtk.economy.transaction").buy_inline(context, Catalog.offering_entry(context))
    if not result.ok then return result.message or { key = "list.action_failed" }, sounds.fail end
    if result.saved == false and (Catalog.config(context).settings or {}).autosave_after_purchase ~= false
        and not require("mvtk.core.checkpoint").is_save_suspended() then
        return { key = "shop.save_failed" }, sounds.fail, true
    end
    return { key = "altar.offered" }, sounds.buy, true
end

local function sell(context, item_id)
    local Transaction = require "mvtk.economy.transaction"
    local Grants = require "mvtk.game.grants"
    local env = Grants.runtime_env()
    local price = require("mvtk.economy.selling").price(item_id, context.sell_share, env.items)
    local result = Transaction.sell(item_id, context)
    local sounds = (require("mvtk.economy.catalog").config(context).settings or {}).sounds or {}
    if not result.ok then return result.message or { key = "list.action_failed" }, sounds.fail end
    if result.saved == false and Transaction.sell_settings(context).autosave_after_purchase ~= false
        and not require("mvtk.core.checkpoint").is_save_suspended() then
        return { key = "shop.save_failed" }, sounds.fail
    end
    local name = require("mvtk.game.grant_spec").item_name(item_id, env)
    return { key = "shop.sold", params = {
        name = type(name) == "table" and name or { text = name }, price = { currency = price },
    } }, sounds.sell or sounds.buy
end

local function bank(context, row_id)
    for _, choice in ipairs(require("mvtk.economy.bank_choices").rows(context.bank_mode)) do
        if choice.id == row_id then
            local ok = require("mvtk.economy.bank")[choice.action](choice.amount)
            if not ok then return { key = "bank.not_enough" } end
            return { key = choice.action == "deposit" and "bank.deposited" or "bank.withdrawn",
                params = { amount = { currency = choice.amount } } }
        end
    end
    return { key = "list.action_failed" }
end

function M.on_message(self, id, message, sender)
    local session = self._station_menu
    if not session or sender ~= msg.url("main:/list_menu_gui#list_menu") then return false end
    message = message or {}
    if message.screen ~= "trade_station" then return false end
    if id == hash("list_menu_closed") then
        self._station_menu = nil
        return true
    end
    if id ~= hash("list_menu_choice") then return false end
    local echo, context = message.context or {}, session.context
    if echo.session_token ~= session.session_token then return false end
    for _, key in ipairs({"station_kind", "station_id", "catalog_id", "room_id"}) do
        if echo[key] ~= context[key] then return false end
    end
    if type(message.token) ~= "number" or message.token < 1 or message.token ~= math.floor(message.token)
        or message.token == math.huge or (session.token and message.token ~= session.token) then return false end
    session.token = message.token
    local status, sfx, purchased
    if context.station_kind == "bank" then
        status, sfx = bank(context, message.row_id)
    elseif context.station_kind == "offering_altar" then
        status, sfx, purchased = offer(context, message.row_id)
    elseif type(message.row_id) == "string" and message.row_id:sub(1, 5) == "sell:" then
        status, sfx = sell(context, message.row_id:sub(6))
    else
        status, sfx, purchased = purchase(context, message.row_id)
    end
    msg.post(sender, "refresh_list_menu", { token = session.token, status = status, sfx = sfx })
    return true, purchased
end

function M.final(self)
    if not self._station_menu then return end
    self._station_menu = nil
    msg.post("main:/list_menu_gui#list_menu", "close_list_menu", { owner = msg.url() })
end

return M
