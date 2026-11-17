-- Presentation only; the baked pedestal authenticates Begin in its own context.
local M = {pause=true}
function M.title(ctx)
    return require("mvtk.ui.trial_text").name((ctx.context or {}).spec or {})
end
function M.rows(ctx)
    local Text = require "mvtk.ui.trial_text"
    local spec = (ctx.context or {}).spec or {}
    local settings, ranks = Text.settings(), {}
    for i=1,3 do
        local threshold = spec["rank_" .. i] or -1
        if threshold >= 0 then
            ranks[#ranks+1] = {key="trial.best",params={rank=Text.rank(settings,i),
                time=spec.trial_goal == "survive" and Text.hits(threshold) or Text.time(math.floor(threshold*10))}}
        end
    end
    local function info(id, value)
        return {id=id,label={key="trial.menu." .. id},value=value,wide_value=true,selectable=false}
    end
    local rows = {
        info("goal",Text.goal(spec)),
        info("time_limit",(spec.time_limit or 0) > 0 and Text.time(math.floor(spec.time_limit*10)) or {key="trial.unlimited"}),
        info("ranks",#ranks > 0 and {parts=ranks,separator={key="trial.separator"}} or {key="trial.no_ranks"}),
        info("best",Text.best(spec,settings)),
        {id="begin",label={key="trial.menu.begin"},confirm={key="trial.menu.begin_confirm"}},
        {id="leave",label={key="trial.menu.leave"}},
    }
    local limits = Text.limits(spec)
    if limits then table.insert(rows,5,info("limits",limits)) end
    local summary = {}
    for i=1,#rows-2 do
        summary[#summary+1] = {key="trial.menu.line",params={label=rows[i].label,value=rows[i].value}}
    end
    for i=#rows-1,#rows do
        rows[i].detail_title = Text.name(spec)
        rows[i].detail = {parts=summary,separator="\n"}
    end
    return rows
end
function M.on_confirm(_, row)
    if row.id == "begin" then return {delegate=true,close=true} end
    if row.id == "leave" then return {close=true} end
    return {}
end
return M
