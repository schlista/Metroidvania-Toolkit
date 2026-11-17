-- Pure curve arithmetic, shared by progression and headless checks.
local M = {}
function M.integer(n, fallback)
    if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then return fallback or 0 end
    return math.max(0, math.floor(n))
end
function M.max_level(cfg) return math.max(1, math.min(99, M.integer(cfg.max_level, 20))) end
function M.xp_to_next(level, cfg)
    if level >= M.max_level(cfg) then return 0 end
    local curve = cfg.curve or {}
    local n = curve.mode == "table" and (curve.table or {})[level] or nil
    if type(n) ~= "number" or n ~= n or n <= 0 or n == math.huge then
        n = math.max(1, M.integer(curve.first, 100)) * (curve.growth or 1.25) ^ (level - 1)
    end
    return math.max(1, M.integer(n, 1))
end
function M.total_for_level(level, cfg)
    local total = 0
    for n = 1, math.min(M.max_level(cfg), math.max(1, M.integer(level, 1))) - 1 do
        total = total + M.xp_to_next(n, cfg)
    end
    return total
end
function M.level_for_xp(xp, cfg)
    xp = M.integer(xp)
    local level, total = 1, 0
    while level < M.max_level(cfg) do
        local needed = M.xp_to_next(level, cfg)
        if xp < total + needed then break end
        total, level = total + needed, level + 1
    end
    return level
end
function M.progress(xp, cfg)
    local level = M.level_for_xp(xp, cfg)
    local max = level == M.max_level(cfg)
    return {level = level, into = max and 0 or M.integer(xp) - M.total_for_level(level, cfg),
        needed = M.xp_to_next(level, cfg), max = max}
end
return M
