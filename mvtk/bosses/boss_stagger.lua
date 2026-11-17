-- Pure, per-boss pressure gauge. The caller owns immunity and stun lifetime.
local M = {}

function M.new(cfg)
    local state = {}
    for k, v in pairs(cfg or {}) do state[k] = v end
    state.threshold = math.max(0, tonumber(state.threshold) or 0)
    M.reset(state)
    return state
end

-- Merge defaults, preset and placed overrides without mutating their tables.
function M.configure(defaults, preset, placed, health_factor)
    local cfg = {}
    for _, layer in ipairs({defaults or {}, preset or {}, (placed or {}).stagger or {}}) do
        for k, v in pairs(layer) do cfg[k] = v end
    end
    for field, key in pairs({stagger_threshold = "threshold", stagger_time = "stun_time",
        stagger_damage_mult = "damage_mult", parry_stagger = "parry_amount",
        stagger_decay_per_s = "decay_per_s"}) do
        local value = tonumber((placed or {})[field])
        if value and value >= 0 then cfg[key] = value end
    end
    cfg.threshold = (tonumber(cfg.threshold) or 0) * health_factor
    return M.new(cfg)
end

function M.add(state, amount)
    if not state or state.threshold <= 0 or state.triggered or amount <= 0 then return false end
    state.value = math.min(state.threshold, state.value + amount)
    state.idle = 0
    state.triggered = state.value >= state.threshold
    return state.triggered
end

function M.tick(state, dt)
    if not state or state.threshold <= 0 or state.triggered then return end
    local before = state.idle
    state.idle = before + math.max(0, dt)
    local delay = state.decay_delay or 0
    local elapsed = math.max(0, state.idle - delay) - math.max(0, before - delay)
    state.value = math.max(0, state.value - elapsed * (state.decay_per_s or 0))
end

function M.fraction(state)
    return state and state.threshold > 0 and state.value / state.threshold or 0
end

function M.reset(state)
    if not state then return end
    state.value, state.idle, state.triggered = 0, 0, false
end

return M
