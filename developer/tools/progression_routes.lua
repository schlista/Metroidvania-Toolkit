-- Report witnesses are a separate unit-cost search, never closure tours.
-- Prune only state that no modeled predicate can observe. An admissible spatial
-- heuristic steers toward still-missing witnesses. Lexical action-order ties
-- retain the old BFS's reward-before-edge ordering and alternative providers.
local Requirements=require "mvtk.world.gates.requirements"
local M={}
local FIELDS={"abilities","items","flags","resources","opened","collected","visited"}
local function copy(t)
    local out={}; for k,v in pairs(t or {}) do out[k]=type(v)=="table" and copy(v) or v end
    return out
end
local function encode(t)
    if type(t)~="table" then
        local value=type(t) .. ":" .. tostring(t)
        return #value .. ":" .. value
    end
    local keys,out={},{}
    for k in pairs(t) do keys[#keys+1]=k end; table.sort(keys)
    for _,k in ipairs(keys) do out[#out+1]=#tostring(k) .. ":" .. tostring(k) .. "=" .. encode(t[k]) end
    return "{" .. table.concat(out,";") .. "}"
end
local function dependencies(graph)
    local used={abilities={},items={},flags={},resources={}}
    local function scan(req)
        for field,ids in pairs(used) do for id in pairs((req or {})[field] or {}) do ids[id]=true end end
        for _,count in ipairs((req or {}).counts or {}) do
            for _,flag in ipairs(count.flags or {}) do used.flags[flag]=true end
        end
        for _,branch in ipairs((req or {}).any or {}) do scan(branch) end
    end
    for _,list in ipairs({graph.edges,graph.rewards,graph.objectives}) do
        for _,entry in ipairs(list) do scan(entry.requirements) end
    end
    for _,e in ipairs(graph.edges) do for id in pairs(e.cost or {}) do used.items[id]=true end end
    local relevant={}
    for _,r in ipairs(graph.rewards) do
        for field,ids in pairs(used) do for id in pairs(r[field] or {}) do
            if ids[id] then relevant[r.id]=true end
        end end
        -- Negative costs are inventory grants too. Positive costs cannot make
        -- an otherwise useless reward necessary for a lower-bound predicate.
        for id,amount in pairs(r.cost or {}) do if amount<0 and used.items[id] then relevant[r.id]=true end end
    end
    return relevant
end
local function observed_openings(graph)
    local live,groups,revoked={},{},{}
    for _,r in ipairs(graph.rewards) do for id,value in pairs(r.abilities or {}) do
        if not value then revoked[id]=true end
    end end
    for _,e in ipairs(graph.edges) do if e.unlock then
        local req=e.requirements or {}
        local signature=encode(req)
        if groups[e.unlock] and groups[e.unlock]~=signature then live[e.unlock]=true end
        groups[e.unlock]=signature
        for field,values in pairs(req) do
            if field~="abilities" and (type(values)~="table" or next(values)) then live[e.unlock]=true end
        end
        for ability in pairs(req.abilities or {}) do if revoked[ability] then live[e.unlock]=true end end
        for _,amount in pairs(e.cost or {}) do if amount~=0 then live[e.unlock]=true end end
    end end
    -- Opening a free gate with the same permanent ability predicate on every
    -- member is unobservable: that predicate stays true for the whole route.
    return live
end
local function signature(s,openings)
    local parts={encode(s.at)}
    for _,field in ipairs(FIELDS) do
        local value=s[field]
        if field=="opened" then
            value={}; for id in pairs(openings) do if s.opened[id] then value[id]=true end end
        end
        parts[#parts+1]=encode(value)
    end
    return table.concat(parts,"|")
end
local function present(o,s)
    local location=o.locations and o.locations[s.at]
    return not o.unknown and not (location and location.unknown)
        and (o.anywhere or (o.locations and location~=nil) or (not o.locations and o.area==s.at))
        and Requirements.evaluate(o.requirements,s)
end
local function route(states,i)
    local out={}
    while i do local s=states[i]; table.insert(out,1,s.step); i=s.parent end
    return out
end
local function snapshot(s)
    local n={at=s.at}
    for _,field in ipairs(FIELDS) do n[field]=copy(s[field]) end
    return n
end
local function grant(s,r)
    s.collected[r.id]=true
    for id,amount in pairs(r.cost or {}) do s.items[id]=(s.items[id] or 0)-amount end
    for id,value in pairs(r.abilities or {}) do s.abilities[id]=value end
    for id,value in pairs(r.flags or {}) do s.flags[id]=value end
    for id,amount in pairs(r.items or {}) do s.items[id]=(s.items[id] or 0)+amount end
end
local function distances(graph,targets)
    local reverse={}
    for _,e in ipairs(graph.edges) do if not e.unknown then
        reverse[e.to]=reverse[e.to] or {}; table.insert(reverse[e.to],e.from)
    end end
    local out={}
    for _,at in ipairs(targets) do if not out[at] then
        local d,q={[at]=0},{at}
        for _,to in ipairs(q) do for _,from in ipairs(reverse[to] or {}) do
            if d[from]==nil then d[from]=d[to]+1; q[#q+1]=from end
        end end
        out[at]=d
    end end
    return out
end
local function before(a,b)
    return a.estimate<b.estimate or (a.estimate==b.estimate and a.order<b.order)
end
local function insert(heap,node)
    local i=#heap+1
    while i>1 do
        local parent=math.floor(i/2)
        if not before(node,heap[parent]) then break end
        heap[i]=heap[parent]; i=parent
    end
    heap[i]=node
end
local function pop(heap)
    local first,last=heap[1],table.remove(heap)
    if #heap>0 then
        local i=1
        while i*2<=#heap do
            local child=i*2
            if child<#heap and before(heap[child+1],heap[child]) then child=child+1 end
            if not before(heap[child],last) then break end
            heap[i]=heap[child]; i=child
        end
        heap[i]=last
    end
    return first
end
local NOTE="Route detail budget reached; showing the full executable route."
function M.build(graph,start,result,opts)
    local clock=opts.clock or os.clock or function() return 0 end
    local deadline=clock()+math.max(0,opts.max_seconds or 0.25)
    local cap=math.max(0,opts.max_states or 12000)
    local relevant,openings=dependencies(graph),observed_openings(graph)
    local pending,remaining={areas={},objectives={},campaign=result.path~=nil},0
    local targets={}
    for _,field in ipairs({"areas","objectives"}) do for id,value in pairs(result[field]) do
        if value.path then pending[field][id]=true; remaining=remaining+1 end
    end end
    for at in pairs(pending.areas) do targets[#targets+1]=at end
    for _,o in ipairs(graph.objectives) do
        if o.locations then for at in pairs(o.locations) do targets[#targets+1]=at end
        elseif not o.anywhere then targets[#targets+1]=o.area end
    end
    if pending.campaign then remaining=remaining+1 end
    local distance=distances(graph,targets)
    local function objective_distance(o,s)
        if s.visited[o.id] then return 0 end
        if o.anywhere then return 0 end
        if not o.locations then return (distance[o.area] or {})[s.at] or math.huge end
        local best=math.huge
        for at,location in pairs(o.locations) do if not location.unknown then
            best=math.min(best,(distance[at] or {})[s.at] or math.huge)
        end end
        return best
    end
    local function heuristic(s)
        local best=math.huge
        for at in pairs(pending.areas) do best=math.min(best,(distance[at] or {})[s.at] or math.huge) end
        local campaign=0
        for _,o in ipairs(graph.objectives) do
            local d=objective_distance(o,s)
            if pending.objectives[o.id] then best=math.min(best,d) end
            if o.required~=false and not s.visited[o.id] then campaign=math.max(campaign,d) end
        end
        if pending.campaign then best=math.min(best,campaign) end
        return best
    end
    local states,seen,heap={},{},{}
    local exhausted=false
    local function push(s,parent,step,order)
        if exhausted or clock()>deadline then exhausted=true; return end
        for _,o in ipairs(graph.objectives) do
            if o.required~=false and present(o,s) then s.visited[o.id]=true end
        end
        s.parent,s.step=parent,step
        s.depth=parent and states[parent].depth+1 or 0
        s.order=order
        local key=signature(s,openings)
        local previous=seen[key] and states[seen[key]]
        if previous and (previous.depth<s.depth or (previous.depth==s.depth and previous.order<=order)) then return end
        if #states>=cap then exhausted=true; return end
        s.estimate=s.depth+heuristic(s)
        if s.estimate==math.huge then return end
        local i=#states+1; states[i]=s; seen[key]=i; s.key=key; s.index=i
        insert(heap,s)
    end
    local function publish(s)
        local i=s.index
        if pending.areas[s.at] then
            result.areas[s.at].path=route(states,i); pending.areas[s.at]=nil; remaining=remaining-1
        end
        local all=true
        for _,o in ipairs(graph.objectives) do
            if o.required~=false and not s.visited[o.id] then all=false end
            if pending.objectives[o.id] and (s.visited[o.id] or present(o,s)) then
                result.objectives[o.id].path=route(states,i); pending.objectives[o.id]=nil; remaining=remaining-1
            end
        end
        if pending.campaign and all then
            result.path=route(states,i); pending.campaign=false; remaining=remaining-1
        end
    end
    local initial=copy(start); initial.at=start.at or graph.start
    for _,field in ipairs(FIELDS) do initial[field]=initial[field] or {} end
    if graph.areas[initial.at] and clock()<=deadline then push(initial,nil,"Start " .. initial.at,"") end
    while remaining>0 and #heap>0 and not exhausted and clock()<=deadline do
        local s=pop(heap)
        local estimate=s.depth+heuristic(s)
        if seen[s.key]==s.index then
            if estimate>s.estimate then
                s.estimate=estimate; insert(heap,s)
            else
                publish(s)
                local rewards=graph.rewards_by_area[s.at] or {}
                for j,r in ipairs(rewards) do
                    if relevant[r.id] and not r.unknown and not s.collected[r.id] and Requirements.evaluate(r.requirements,s) then
                        local n=snapshot(s); grant(n,r)
                        push(n,s.index,"Collect " .. r.id,s.order .. string.format("%08d",j))
                    end
                end
                for j,e in ipairs(graph.outgoing[s.at] or {}) do
                    local open=e.unlock and s.opened[e.unlock]
                    if not e.unknown and (open or Requirements.evaluate(e.requirements,s)) then
                        local n=snapshot(s); n.at=e.to
                        if not open then
                            for id,amount in pairs(e.cost or {}) do n.items[id]=(n.items[id] or 0)-amount end
                            if e.unlock then n.opened[e.unlock]=true end
                        end
                        push(n,s.index,"Traverse " .. e.id .. " -> " .. e.to,s.order .. string.format("%08d",#rewards+j))
                    end
                end
            end
        end
    end
    for _,field in ipairs({"areas","objectives"}) do for id in pairs(pending[field]) do result[field][id].path_note=NOTE end end
    if pending.campaign then result.path_note=NOTE end
    result.route_states=#states
end
return M
