-- Pure encounter membership. Door cleanup has a deliberately broader room
-- fallback; an unlocked boss never joins this save/music group.
local M = {}

function M.key(boss)
    local value = boss and boss.config and boss.config.arena
    if type(value) == "string" and value:match("%S") then return value end
end

function M.members(active, key)
    local out = {}
    if not key then return out end
    for id, boss in pairs(active) do
        if M.key(boss) == key then out[#out + 1] = id end
    end
    table.sort(out, function(a, b)
        -- Generated runtime ids follow the deterministic placement start order,
        -- including digit boundaries; other caller-supplied ids sort as text.
        local an = tostring(a):match("^boss_(%d+)$")
        local bn = tostring(b):match("^boss_(%d+)$")
        if an and bn and tonumber(an) ~= tonumber(bn) then return tonumber(an) < tonumber(bn) end
        return tostring(a) < tostring(b)
    end)
    return out
end

function M.live_members(active, key)
    local out = {}
    for _, id in ipairs(M.members(active, key)) do
        if not active[id].defeated then out[#out + 1] = id end
    end
    return out
end

function M.lead(active, key)
    return M.members(active, key)[1]
end

-- Called after marking the dying member defeated.
function M.is_last(active, key)
    return #M.live_members(active, key) == 0
end

function M.encounter_members(active, boss_id)
    local key = M.key(active[boss_id])
    return key and M.members(active, key) or {boss_id}
end

function M.highest_live_phase(active, arena_id, phase_of)
    local phase, found, locked = 0, false, false
    for id, boss in pairs(active) do
        local cfg = boss.config or {}
        if not boss.defeated and (cfg.arena_id == arena_id or cfg.arena == arena_id) then
            phase = math.max(phase, phase_of(id))
            found = true
            locked = locked or M.key(boss) ~= nil
        end
    end
    return phase, found, locked
end

-- Select the latest defeated member with a scene, falling back to the lead.
function M.defeat_scene(active, members)
    local chosen, order = nil, -1
    for _, id in ipairs(members) do
        local boss = active[id]
        local scene = boss.config.defeat_cutscene
        if type(scene) == "string" and scene ~= "" and scene ~= "none"
            and (boss.group_defeat_order or 0) > order then
            chosen, order = scene, boss.group_defeat_order or 0
        end
    end
    return chosen
end

function M.should_advance(active, boss_id, current, next_phase)
    local members = M.encounter_members(active, boss_id)
    if #members < 2 then return true, false end
    local highest = current
    for _, id in ipairs(members) do
        highest = math.max(highest, active[id].group_arena_phase or 0)
    end
    return next_phase > highest, true
end

-- Pools belong to the manager's encounter lifetime. Maxima are already scaled
-- at spawn; each member retains its own defenses, i-frames and stagger state.
function M.join_pool(groups, active, boss_id)
    local boss = active[boss_id]
    local key = M.key(boss)
    if not key or boss.config.shared_health ~= true then return end
    local pool = groups[key]
    if not pool or #M.live_members(active, key) == 1 then
        pool = {key=key, pool=0, pool_max=0, members={}}
        groups[key] = pool
    end
    pool.members[#pool.members + 1] = boss_id
    pool.pool_max = pool.pool_max + boss.max_health
    pool.pool = pool.pool + boss.max_health
    pool.lead = M.lead(active, key)
    boss.shared_pool = pool
    -- A later spawn may join after accepted damage; keep health mirrors and
    -- the common boss-phase fraction consistent with the enlarged pool.
    for _, id in ipairs(pool.members) do
        active[id].health = active[id].max_health * pool.pool / pool.pool_max
    end
end

local function mirror_pool_health(active, pool)
    for _, id in ipairs(pool.members) do
        local member = active[id]
        if member and not member.defeated then
            member.health = member.max_health * pool.pool / pool.pool_max
        end
    end
end

function M.phase_damage_boundary(active, boss, health, max_health)
    local edge
    local pool = boss.shared_pool
    for _, id in ipairs(pool and pool.members or {boss.id}) do
        local member = active[id]
        local pc = member and member.phase_controller
        if pc and pc.get_damage_boundary and not member.defeated and member.config.phase_damage_gate then
            local boundary = pc:get_damage_boundary(health, max_health)
            if boundary and (not edge or boundary > edge) then edge = boundary end
        end
    end
    return edge
end

function M.set_health(active, boss, remaining_health)
    local pool = boss.shared_pool
    if not pool then boss.health = remaining_health; return end
    pool.pool = remaining_health
    mirror_pool_health(active, pool)
end

function M.apply_heal(active, boss, amount)
    local pool = boss.shared_pool
    if not pool then
        boss.health = math.min(boss.max_health, boss.health + amount)
        return
    end
    pool.pool = math.min(pool.pool_max, pool.pool + amount)
    mirror_pool_health(active, pool)
end

function M.finish_damage(active, boss_id, source, kill)
    local boss = active[boss_id]
    if boss.health > 0 then return end
    for _, id in ipairs(boss.shared_pool and boss.shared_pool.members or {boss_id}) do
        if active[id] and not active[id].defeated then kill(id, source) end
    end
end

function M.partner_defeated(active, boss_id)
    local boss = active[boss_id]
    if boss.shared_pool then return end -- Shared members fall together.
    for _, id in ipairs(M.live_members(active, M.key(boss))) do
        local pc = active[id].phase_controller
        if pc then
            for i, phase in ipairs(pc.phases or {}) do
                if phase.partner_defeated and i > pc.current_phase_index then
                    pc:hold_at_least(i)
                    break
                end
            end
        end
    end
end

function M.ui_id(boss)
    return boss.shared_pool and boss.shared_pool.key or boss.id
end

function M.bar_state(active, boss)
    local pool = boss.shared_pool
    local lead = pool and active[pool.lead] or boss
    local name = pool and boss.config.group_name
    return {
        id = M.ui_id(boss), hp = pool and pool.pool or boss.health,
        hp_max = pool and pool.pool_max or boss.max_health,
        name = type(name) == "string" and name:match("%S") and name or lead.config.name,
        lead = lead,
    }
end

return M
