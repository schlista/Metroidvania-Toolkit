-- Transient FIFO. Only waiting notices can be replaced or evicted.
local M = {}
function M.new(cfg)
    cfg = cfg or {}
    return { pending = {}, elapsed = 0, max_queue = math.max(1, cfg.max_queue or 6),
        duration = math.max(0, cfg.duration or 2.5), fade_in = math.max(0, cfg.fade_in or 0.15),
        fade_out = math.max(0, cfg.fade_out or 0.25) }
end
function M.push(q, notice)
    if notice.key and notice.key ~= "" then
        for i, queued in ipairs(q.pending) do
            if queued.key == notice.key then q.pending[i] = notice; return end
        end
    end
    if #q.pending >= q.max_queue then table.remove(q.pending, 1) end
    q.pending[#q.pending + 1] = notice
end
function M.tick(q, dt, frozen)
    if frozen then return q.current, q.alpha or 0 end
    if q.current then
        q.elapsed = q.elapsed + math.max(0, dt)
        if q.elapsed >= q.fade_in + q.duration + q.fade_out then q.current = nil end
    end
    -- A large frame never skips an unseen notice.
    if not q.current then q.current = table.remove(q.pending, 1); q.elapsed = 0 end
    local alpha = 1
    if not q.current then alpha = 0
    elseif q.fade_in > 0 and q.elapsed < q.fade_in then alpha = q.elapsed / q.fade_in
    elseif q.fade_out > 0 and q.elapsed > q.fade_in + q.duration then
        alpha = 1 - (q.elapsed - q.fade_in - q.duration) / q.fade_out
    end
    q.alpha = alpha
    return q.current, alpha
end
return M
