-- Source descriptions only. The displaying GUI resolves names, plurals and time.
local M = {}
function M.time(tenths)
    return require("mvtk.ui.time_text").playtime(math.floor(tenths / 10), tenths % 10)
end
function M.hits(count)
    return {forms={one="trial.hits_one",other="trial.hits_other"}, count=count, params={count=count}}
end
function M.name(spec)
    return spec.trial_name and spec.trial_name ~= "" and {text=spec.trial_name} or {key="trial.default_name"}
end
function M.goal(spec)
    local goal = spec.trial_goal or "clear"
    local text
    if goal == "defeat_count" then
        local count = spec.defeat_target or 1
        text = {forms={one="trial.goal.defeat_count_one",other="trial.goal.defeat_count_other"},
            count=count, params={count=count}}
    elseif goal == "survive" then
        text = {key="trial.goal.survive",params={time=M.time(math.floor((spec.time_limit or 0)*10))}}
    else text = {key="trial.goal.clear"} end
    if spec.no_damage then return {parts={text,{key="trial.no_damage"}},separator={key="trial.separator"}} end
    return text
end
function M.limits(spec)
    local Limits = require "mvtk.game.trial_limits"
    local parts = {}
    local definitions = require("developer.config.abilities").abilities
    for _, id in ipairs(Limits.ids(spec.disabled_abilities)) do
        local def = definitions[id]
        parts[#parts+1] = def and def.name and def.name ~= "" and {text=def.name} or {key="list.missing_name"}
    end
    for _, tag in ipairs(Limits.ids(spec.disabled_attacks)) do
        parts[#parts+1] = {key="trial.attack." .. tag}
    end
    if #parts == 0 then return nil end
    return {key="trial.limits",params={moves={parts=parts,separator={key="trial.limit_separator"}}}}
end
function M.settings()
    return require("developer.config.runtime_settings").section("trial_settings",require "developer.config.trial_settings")
end
function M.rank(settings, rank)
    local entry = settings.ranks[rank]
    return entry and {text=entry.name} or ""
end
function M.best(spec, settings, flags)
    flags = flags or require "mvtk.core.flags"
    local id = spec.trial_id
    if not id or id == "" then return {key="trial.not_cleared"} end
    local metric = flags.get("trial_best_" .. id)
    if metric == nil then return {key="trial.not_cleared"} end
    return {key="trial.best",params={rank=M.rank(settings,flags.get("trial_rank_" .. id) or 0),
        time=spec.trial_goal == "survive" and M.hits(metric) or M.time(metric)}}
end
return M
