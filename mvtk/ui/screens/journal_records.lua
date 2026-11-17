-- Shared Records surface. Later features register sections by stable id.
local M = {}


function M.new(deps)
  deps = deps or {}
  local provider, sections = {}, {}
  function provider.add_section(section)
    assert(type(section.id) == "string" and section.id ~= "", "Records section needs an id")
    sections[section.id] = section
  end
  function provider.sections()
    local out = {}
    for _, section in pairs(sections) do out[#out + 1] = section end
    table.sort(out, function(a, b)
      if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
      return a.id < b.id
    end)
    return out
  end
  function provider.title() return { key = "journal.records" } end
  function provider.enabled()
    local settings = (deps.menu_nav or require "mvtk.ui.menu_nav").settings() or {}
    return (((settings.books or {}).journal) or {}).show_records ~= false
  end
  function provider.rows(ctx)
    local out = {}
    for _, section in ipairs(provider.sections()) do
      if not section.visible or section.visible(ctx) then
        out[#out + 1] = { id = section.id, kind = "section", label = section.header(ctx), selectable = false }
        for i, line in ipairs(section.lines(ctx)) do
          out[#out + 1] = { id = section.id .. ":" .. i, label = line.label, value = line.value, wide_value = line.wide_value, selectable = false }
        end
      end
    end
    return out
  end
  function provider.header_right(ctx)
    for _, section in ipairs(provider.sections()) do
      if section.summary and (not section.visible or section.visible(ctx)) then
        local summary = section.summary(ctx)
        if type(summary) == "table" or (type(summary) == "string" and summary:find("%S")) then return summary end
      end
    end
  end
  provider.add_section({ id = "time", order = 10, header = function() return { key = "journal.time" } end,
    lines = function()
      local lines = { { label = { key = "journal.play_time" }, value = require("mvtk.ui.time_text").playtime((deps.checkpoint or require "mvtk.core.checkpoint").playtime_s()) } }
      if require("mvtk.player.assist").record_use() and (deps.flags or require "mvtk.core.flags").get("assist_used") == true then
        lines[#lines + 1] = {label = {key = "records.assist_used"}, value = ""}
      end
      return lines
    end })
  provider.add_section({ id = "collection", order = 30, header = function() return { key = "journal.collection" } end,
    lines = function()
      local catalog = require("mvtk.ui.screens.journal_collection").new(deps)
      return { { label = { key = "journal.relics" }, value = catalog.progress("relic") }, { label = { key = "journal.lore" }, value = catalog.progress("lore") } }
    end })
  provider.add_section({ id = "currency", order = 50, header = function() return { key = "journal.currency" } end,
    lines = function()
      return { { label = { key = "journal.currency" }, value = { currency = (deps.inventory or require "mvtk.core.inventory").get_currency(), formatter = deps.currency_text } } }
    end })
  -- Resolve configuration and profile data when Records opens, never at bootstrap.
  local function endings()
    local cfg = deps.ending_config or require("developer.config.runtime_settings").section(
      "game_completion", require "developer.config.game_completion")
    return require("mvtk.game.endings").list(cfg)
  end
  local function ending_records()
    return (deps.profile or require "mvtk.core.profile_store").get("records")
  end
  provider.add_section({ id = "endings", order = 70,
    visible = function() return #endings() > 0 end,
    header = function()
      local list, seen, found = endings(), ending_records().endings_seen or {}, 0
      for _, ending in ipairs(list) do if seen[ending.id] == true then found = found + 1 end end
      return {forms={one="records.endings_one", other="records.endings_other"}, count=#list, params={found=found, total=#list}}
    end,
    lines = function()
      local records, lines = ending_records(), {}
      for _, ending in ipairs(endings()) do
        if (records.endings_seen or {})[ending.id] == true then
          local seconds = (records.best_times or {})[ending.id]
          local time = type(seconds)=="number" and seconds==seconds and seconds>=0 and seconds<math.huge
            and require("mvtk.ui.time_text").playtime(seconds) or {key="journal.unknown"}
          lines[#lines+1] = {label=require("mvtk.ui.menu_text").default(
            type(ending.title)=="string" and ending.title:match("%S") and ending.title or nil, "journal.unknown"),
            value={key="records.best_time", params={time=time}}, wide_value=true}
        end
      end
      return lines
    end })
  provider.add_section({ id = "trials", order = 75, header = function() return {key="records.trials"} end,
    visible = function()
      for _, entry in ipairs((deps.census or require "mvtk.world.census").entries()) do
        if entry.kind == "trial" then return true end
      end
      return false
    end,
    lines = function()
      local Text = require "mvtk.ui.trial_text"
      local settings, lines = deps.trial_settings or Text.settings(), {}
      for _, entry in ipairs((deps.census or require "mvtk.world.census").entries()) do
        if entry.kind == "trial" then
          local spec = {trial_id=entry.id,trial_name=entry.name,trial_goal=entry.trial_goal}
          lines[#lines+1] = {label=Text.name(spec),value=Text.best(spec,settings,deps.flags),wide_value=true}
        end
      end
      return lines
    end })
  -- Countdown events (WM09): best times of countdowns that keep one.
  local function countdown_rows()
    local Rules = require "mvtk.game.countdown_rules"
    local cfg = deps.countdowns or require("developer.config.runtime_settings").section(
      "countdowns", require "developer.config.countdowns")
    local flags, rows = deps.flags or require "mvtk.core.flags", {}
    for _, id in ipairs(Rules.ids(cfg)) do
      local spec = Rules.entry(cfg, id)
      local best = spec and spec.best_time and flags.get(Rules.best_flag(id))
      if type(best) == "number" and best == best and best >= 0 and best < math.huge then
        rows[#rows + 1] = { spec = spec, tenths = math.floor(best) }
      end
    end
    return rows
  end
  provider.add_section({ id = "countdowns", order = 77, header = function() return { key = "records.countdowns" } end,
    visible = function() return #countdown_rows() > 0 end,
    lines = function()
      local lines, TimeText = {}, require "mvtk.ui.time_text"
      for _, row in ipairs(countdown_rows()) do
        lines[#lines + 1] = { label = require("mvtk.ui.menu_text").default(
          type(row.spec.label) == "string" and row.spec.label:match("%S") and row.spec.label or nil, "journal.unknown"),
          value = { key = "records.best_time", params = { time = TimeText.playtime(math.floor(row.tenths / 10), row.tenths % 10) } },
          wide_value = true }
      end
      return lines
    end })
  return provider
end

local default = M.new()
default.new = M.new
return default
