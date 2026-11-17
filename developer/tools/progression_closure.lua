-- Pure search helpers. A closure may only add state, and may only merge
-- locations with a currently usable, cost-free route in both directions.
local M={}
local function costly(cost)
    for _,amount in pairs(cost or {}) do if amount~=0 then return true end end
    return false
end
M.costly=costly
function M.monotone_rewards(graph)
    local sensitive,values,revoked={},{},{}
    local function requirements(req)
        for flag,value in pairs((req or {}).flags or {}) do
            if value~=true then sensitive[flag]=true end
        end
        for _,branch in ipairs((req or {}).any or {}) do requirements(branch) end
    end
    for _,list in ipairs({graph.edges,graph.objectives,graph.rewards}) do
        for _,entry in ipairs(list) do requirements(entry.requirements) end
    end
    for _,r in ipairs(graph.rewards) do
        for flag,value in pairs(r.flags or {}) do
            if values[flag]~=nil and values[flag]~=value then sensitive[flag]=true end
            values[flag]=value
        end
        for ability,value in pairs(r.abilities or {}) do if not value then revoked[ability]=true end end
    end
    local safe={}
    for _,r in ipairs(graph.rewards) do
        local ok=not costly(r.cost)
        for flag,value in pairs(r.flags or {}) do if sensitive[flag] or value==false then ok=false end end
        for ability,value in pairs(r.abilities or {}) do if not value or revoked[ability] then ok=false end end
        for _,amount in pairs(r.items or {}) do if amount<0 then ok=false end end
        safe[r.id]=ok
    end
    return safe
end

function M.component(graph,state,allowed)
    local outgoing,reverse={},{}
    for _,e in ipairs(graph.edges) do
        if (state.opened[e.unlock] or not costly(e.cost)) and allowed(e,state) then
            outgoing[e.from]=outgoing[e.from] or {}; table.insert(outgoing[e.from],e.to)
            reverse[e.to]=reverse[e.to] or {}; table.insert(reverse[e.to],e.from)
        end
    end
    local function flood(edges)
        local seen,q={[state.at]=true},{state.at}
        for _,at in ipairs(q) do for _,to in ipairs(edges[at] or {}) do
            if not seen[to] then seen[to]=true; q[#q+1]=to end
        end end
        return seen
    end
    local forward,backward=flood(outgoing),flood(reverse)
    local members,ordered={},{}
    for at in pairs(forward) do if backward[at] then members[at]=true; ordered[#ordered+1]=at end end
    table.sort(ordered)
    return members,ordered
end

function M.route(graph,state,target,members,allowed)
    local seen,q,via={[state.at]=true},{state.at},{}
    for _,at in ipairs(q) do
        if at==target then break end
        for _,e in ipairs(graph.outgoing[at] or {}) do
            if members[e.to] and not seen[e.to] and (state.opened[e.unlock] or not costly(e.cost)) and allowed(e,state) then
                seen[e.to]=true; q[#q+1]=e.to; via[e.to]=e
            end
        end
    end
    assert(seen[target],"Closure route must stay reversible")
    local route,at={},target
    while at~=state.at do local e=via[at]; table.insert(route,1,e); at=e.from end
    return route
end
return M
