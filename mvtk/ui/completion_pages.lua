-- Pure ending presentation shared by the game and editor previews.
-- Page one includes session statistics (none when data.replay is set);
-- subsequent pages contain credit lines.
local M = {}
local English = require "developer.config.ui_text"
local TimeText = require "mvtk.ui.time_text"

-- The creator preview stays English and engine-free. The game supplies its
-- DisplayText functions each time it draws; no rendered page is saved.
local function english_ui(key, params)
    return (English[key] or key):gsub("{([%w_]+)}", function(name)
        return params and params[name] ~= nil and tostring(params[name]) or "{" .. name .. "}"
    end)
end

function M.build(cfg, data, display)
    data = data or {}
    local render = display and display.render or function(value) return value end
    local ui = display and display.ui or english_ui
    local per_page = math.max(1, math.floor(cfg.credits_per_page or 8))
    local credits = {}
    for line in render(cfg.credits or ""):gmatch("[^\n]+") do credits[#credits + 1] = line end
    local count = 0
    for _, amount in pairs((data.stats or {}).items or {}) do count = count + amount end
    local minutes = math.floor((data.playtime_s or 0) / 60)
    local forms = {one="completion.stats_one",other="completion.stats_other"}
    local key = display and display.plural_form and display.plural_form(forms, minutes)
        or (minutes == 1 and forms.one or forms.other)
    local percent = (data.stats or {}).completion_percent
    local has_percent = type(percent)=="number"
    local stats
    if data.run_time_s ~= nil then
        local time = TimeText.playtime(data.run_time_s)
        stats = ui(has_percent and "completion.stats_time_percent" or "completion.stats_time", {time=ui(time.key, time.params),count=count,percent=percent})
    else
        if has_percent then
            forms = {one="completion.stats_percent_one",other="completion.stats_percent_other"}
            key = display and display.plural_form and display.plural_form(forms,minutes) or (minutes==1 and forms.one or forms.other)
        end
        stats = ui(key, {minutes=minutes,count=count,percent=percent})
    end
    if not data.replay and display and display.assist_used then
        stats = stats .. "\n" .. ui("completion.stats_assist_used")
    end
    local body = render(cfg.body)
    local pages = {{title = render(cfg.title), text = body, stats = stats,
        body = ui("completion.body", {body=body,stats=stats}), artwork = cfg.artwork}}
    -- Extras credits replay: the ending text alone, with no statistics line.
    if data.replay then pages[1] = {title = pages[1].title, text = body, body = body, artwork = cfg.artwork} end
    for first = 1, #credits, per_page do
        local rows = {}
        for i = first, math.min(#credits, first + per_page - 1) do rows[#rows + 1] = credits[i] end
        local body = table.concat(rows, "\n")
        pages[#pages + 1] = {title = ui("completion.credits"), text = body, body = body}
    end
    return pages, {credits = credits, per_page = per_page}
end

return M
