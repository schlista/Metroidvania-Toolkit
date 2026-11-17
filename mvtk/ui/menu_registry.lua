-- Providers are required statically for the bundle, but load no engine state.
local InventoryCrafting = require "mvtk.ui.screens.inventory_crafting"
local InventoryCharms = require "mvtk.ui.screens.inventory_charms"
local InventoryWeapons = require "mvtk.ui.screens.inventory_weapons"
local InventoryItems = require "mvtk.ui.screens.inventory_items"
local Goals = require "mvtk.ui.screens.journal_goals"
local Quests = require "mvtk.game.quests.quest_journal"
local Bestiary = require "mvtk.ui.screens.bestiary"
local JournalPeople = require "mvtk.ui.screens.journal_people"
local Achievements = require "mvtk.ui.screens.achievements"
local JournalRelics = require "mvtk.ui.screens.journal_relics"
local JournalLore = require "mvtk.ui.screens.journal_lore"
local JournalRecords = require "mvtk.ui.screens.journal_records"
local CombatTrial = require "mvtk.ui.screens.combat_trial"
local ElevatorLandings = require "mvtk.ui.screens.elevator_landings"
local TradeStation = require "mvtk.ui.screens.trade_station"
local ExtrasJukebox = require "mvtk.ui.screens.extras_jukebox"
local ExtrasCredits = require "mvtk.ui.screens.extras_credits"
local ExtrasGallery = require "mvtk.ui.screens.extras_gallery"
local PauseModel = require "mvtk.ui.pause_menu_model"
local M = {}

function M.new(deps)
  deps = deps or {}
  local registry = { screens = deps.screens or { elevator_landings = ElevatorLandings, trade_station = TradeStation, combat_trial = CombatTrial }, books = deps.books or {
    inventory = { tabs = { { id = "items", order = 10, provider = InventoryItems }, { id = "weapons", order = 20, provider = InventoryWeapons }, { id = "charms", order = 30, provider = InventoryCharms }, { id = "crafting", order = 40, provider = InventoryCrafting } } },
    journal = { tabs = {
      { id = "goals", order = 10, provider = Goals },
      { id = "quests", order = 20, provider = Quests },
      { id = "bestiary", order = 30, provider = Bestiary },
      { id = "people", order = 35, provider = JournalPeople },
      { id = "relics", order = 40, provider = JournalRelics },
      { id = "lore", order = 50, provider = JournalLore },
      { id = "achievements", order = 60, provider = Achievements },
      { id = "records", order = 70, provider = JournalRecords },
    } },
    -- Opened from the title's Extras proxy (jukebox 10, gallery 20, credits 30).
    -- A book with no enabled tab refuses to open.
    extras = { tabs = {
      { id = "jukebox", order = 10, provider = ExtrasJukebox },
      { id = "gallery", order = 20, provider = ExtrasGallery },
      { id = "credits", order = 30, provider = ExtrasCredits },
    } },
  } }
  local warned = {}
  local function failed(key, err)
    if not warned[key] then
      warned[key] = true
      (deps.log or print)("[LIST_MENU] Provider " .. key .. ": " .. tostring(err))
    end
  end
  function registry.screen(id) return registry.screens[id] end
  function registry.tabs(book, ctx)
    ctx = ctx or {}; ctx.registry = registry
    local out = {}
    for _, tab in ipairs((registry.books[book] or {}).tabs or {}) do
      local ok, enabled = pcall(function()
        return not tab.provider.enabled or tab.provider.enabled(ctx)
      end)
      if ok and enabled then
        local title_ok, title = pcall(tab.provider.title, ctx)
        if title_ok then
          out[#out + 1] = { id = tab.id, order = tab.order or 0, provider = tab.provider, title = title }
        else failed(book .. "/" .. tab.id, title) end
      elseif not ok then failed(book .. "/" .. tab.id, enabled) end
    end
    table.sort(out, function(a, b) return a.order == b.order and a.id < b.id or a.order < b.order end)
    return out
  end
  function registry.has_enabled_tab(book, ctx) return #registry.tabs(book, ctx) > 0 end
  function registry.owns_item(id)
    local function owns(provider, key)
      if not provider.owns_item then return false end
      local ok, owned = pcall(provider.owns_item, id)
      if not ok then failed(key, owned); return false end
      return owned == true
    end
    for key, provider in pairs(registry.screens) do if owns(provider, key) then return true end end
    for book, value in pairs(registry.books) do
      for _, tab in ipairs(value.tabs) do
        if owns(tab.provider, book .. "/" .. tab.id) then return true end
      end
    end
    return false
  end
  return registry
end

local default = M.new()
default.new = M.new

local function open_book(book)
  local ok = pcall(msg.post, "main:/list_menu_gui#list_menu", "open_list_menu",
    { book = book, opener = "pause_menu" })
  return { close = ok }
end

PauseModel.register_entry("journal", {
  after = "inventory",
  visible = function(ctx) return default.has_enabled_tab("journal", ctx) end,
  run = function() return open_book("journal") end,
})
PauseModel.register_entry("inventory", {
  replace = true,
  run = function() return open_book("inventory") end,
})
return default
