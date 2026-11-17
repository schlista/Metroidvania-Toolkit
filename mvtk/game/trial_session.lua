-- Pure trial rules. Exposed times, metrics and saved records are integer tenths.
-- Fractional frame time is carried privately until it forms a complete tenth.
local M = {}
local function tenths(seconds) return math.floor(math.max(0, seconds or 0) * 10 + 0.0000001) end
local function finish(s, result, reason)
    if not s.finished then s.finished = {result=result, reason=reason} end
end
function M.new(spec)
    return {spec=spec, elapsed=0, remainder=0, hits=0, defeats=0,
        limit=tenths(spec.time_limit), goal=spec.goal or spec.trial_goal or "clear"}
end
function M.tick(s, dt)
    if s.finished then return end
    dt = tonumber(dt) or 0
    if dt ~= dt or dt == math.huge then return end
    local total = s.remainder + math.max(0, dt)
    local ticks = tenths(total)
    s.remainder = total - ticks / 10
    s.elapsed = s.elapsed + ticks
    if s.limit > 0 and s.elapsed >= s.limit then
        s.elapsed = s.limit
        finish(s, s.goal == "survive" and "success" or "failure", "time")
    end
end
function M.on_cleared(s, room_id, encounter_id)
    if room_id ~= s.spec.room_id or encounter_id ~= s.spec.encounter_id then return end
    if s.goal == "defeat_count" and s.defeats < (s.spec.defeat_target or 1) then
        finish(s, "failure", "incomplete")
    else finish(s, "success", "cleared") end
end
function M.on_defeat(s, owner)
    if s.finished or owner ~= s.spec.encounter_owner then return end
    s.defeats = s.defeats + 1
    if s.goal == "defeat_count" and s.defeats >= (s.spec.defeat_target or 1) then
        finish(s, "success", "defeats")
    end
end
function M.on_damage(s, amount)
    if s.finished or (amount or 0) <= 0 then return end
    s.hits = s.hits + 1
    if s.spec.no_damage then finish(s, "failure", "hit") end
end
function M.on_death(s)
    -- A lethal hit must never be turned into a clear in the same frame.
    s.finished = {result="failure", reason="defeated"}
end
function M.outcome(s) return s.finished end
function M.metric(s) return s.goal == "survive" and s.hits or s.elapsed end
function M.rank(spec, metric)
    local survive = (spec.goal or spec.trial_goal) == "survive"
    for i=1,3 do
        local threshold = spec["rank_" .. i] or -1
        if threshold >= 0 and metric <= (survive and threshold or tenths(threshold)) then return i end
    end
    return 0
end
function M.better(old_rank, old_metric, rank, metric)
    if old_metric == nil then return true end
    old_rank = old_rank or 0
    if rank ~= old_rank then return rank > 0 and (old_rank == 0 or rank < old_rank) end
    return metric < old_metric
end
return M
