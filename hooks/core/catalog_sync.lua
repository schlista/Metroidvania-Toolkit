-- Shared first-stage dropdown sync. Validate every source before any write.
local Carriers = require "mvtk.tiled.tiled_carriers"
local Registry = require "mvtk.tiled.catalog_enums"
local Fresh = require "mvtk.editor.fresh_config"
local M = {}
M.REOPEN = "In Tiled, close and reopen MVTK.tiled-project (File > Open File or Project...)."

function M.summary(result)
    if not result or #result.changed_files==0 then return nil end
    local names={};for name in pairs(result.changes) do names[#names+1]=name end;table.sort(names)
    return "Tiled dropdowns changed: "..table.concat(names,", ")..". "..M.REOPEN
end

local function difference(a,b)
    local set,out={},{};for _,v in ipairs(b) do set[v]=true end
    for _,v in ipairs(a) do if not set[v] then out[#out+1]=v end end
    return out
end

function M.sync_enums(deps,opts)
    opts=opts or {}
    local info=deps.info or function() end
    local root=tostring(deps.root or "."):gsub("\\","/"):gsub("/$","")
    local texts,scans,by_name={},{},{}
    for i,path in ipairs(Carriers.PATHS) do
        texts[i]=deps.read(root.."/"..path)
        local err
        scans[i],err=Carriers.property_types(texts[i])
        if not scans[i] then return nil,path..": "..tostring(err).."; restore the carrier" end
        by_name[i]={}
        for _,entry in ipairs(scans[i]) do
            if type(entry.id)~="number" or entry.id<0 or entry.id~=math.floor(entry.id)
                or (entry.type~="enum" and entry.type~="class") then
                return nil,path..": invalid type or id for "..entry.name.."; restore the carrier"
            end
            if by_name[i][entry.name] then return nil,path..": duplicate type name "..entry.name end
            by_name[i][entry.name]=entry
        end
        local duplicates=Carriers.duplicate_ids(scans[i])
        if #duplicates>0 then local d=duplicates[1];return nil,path..": duplicate id "..d.id.." ("..d.first..", "..d.second.."); assign unique ids" end
    end
    local fresh=deps.load or Fresh.new({root=root,read=deps.read})
    local function load(name)
        local path=name:gsub("%.","/")..".lua"
        if type(fresh)=="function" then return fresh(name) end
        return fresh.load_path(path)
    end
    local rows=opts.rows or Registry.rows()
    local ordered={}
    for _,row in ipairs(rows) do if row.kind~="enum" then ordered[#ordered+1]=row end end
    for _,row in ipairs(rows) do if row.kind=="enum" then ordered[#ordered+1]=row end end
    local prepared,derived_by_name={},{}
    for _,row in ipairs(ordered) do
        if row.kind~="external" then
            local derived,entries,state,missing
            if row.kind=="enum" and derived_by_name[row.enum] then
                derived={}
                for _,v in ipairs(derived_by_name[row.enum]) do derived[#derived+1]=v end
                local valid,err=Registry.check_values(row,derived)
                if not valid then return nil,err end
            else
                derived,entries,state,missing=Registry.derive(row,load,texts[1],scans[1])
            end
            if not derived then
                if state=="missing" then info("[CATALOGS] Warning: missing "..tostring(missing).."; keeping "..row.name)
                else return nil,tostring(entries) end
            else
                local existing={}
                if by_name[1][row.name] then
                    local err;existing,err=Carriers.enum_values(texts[1],row.name,scans[1]);if not existing then return nil,err end
                end
                local values=Registry.merge(existing,derived,row,entries)
                prepared[#prepared+1]={row=row,values=values};derived_by_name[row.name]=values
                local valid={};for _,v in ipairs(values) do valid[v]=true end
                for _,usage in ipairs(deps.usage or require("mvtk.tiled.enum_usage")) do
                    if usage.enum==row.name and usage.default~="" and not valid[usage.default] then
                        info("[CATALOGS] Warning: "..usage.template.." default "..tostring(usage.default).." left "..(row.module or row.name))
                    end
                end
            end
        end
    end
    local next_id=Carriers.next_id(scans,deps.floor or require("mvtk.core.product").property_type_id_floor)
    local edits,new_rows,used={},{},{}
    for i,scan in ipairs(scans) do
        edits[i],new_rows[i],used[i]={},{},{}
        for _,entry in ipairs(scan) do used[i][entry.id]=true end
    end
    local result={changed_files={},changes={}}
    for _,item in ipairs(prepared) do
        local row,values=item.row,item.values
        local shared_id
        for i=1,#texts do local entry=by_name[i][row.name];if entry then shared_id=shared_id or entry.id end end
        if not shared_id then shared_id=next_id;next_id=next_id+1 end
        local change={added={},removed={},created=false}
        for i,text in ipairs(texts) do
            local entry=by_name[i][row.name]
            if entry then
                local old,err=Carriers.enum_values(text,row.name,scans[i]);if not old then return nil,err end
                local edit;edit,err=Carriers.values_edit(text,row.name,values,scans[i]);if not edit then return nil,err end
                local flags_edit=Carriers.flags_edit(text,entry,row.flags)
                if edit.text~=text:sub(edit.start,edit.finish) then
                    edits[i][#edits[i]+1]=edit
                    if not result.changes[row.name] then change.added=difference(values,old);change.removed=difference(old,values) end
                    result.changes[row.name]=change
                end
                if flags_edit then edits[i][#edits[i]+1]=flags_edit;result.changes[row.name]=change end
            else
                local id=shared_id
                if used[i][id] then id=next_id;next_id=next_id+1 end
                used[i][id]=true
                new_rows[i][#new_rows[i]+1]={id=id,name=row.name,values=values,flags=row.flags}
                change.created=true;change.added=values;result.changes[row.name]=change
            end
        end
    end
    local outputs={}
    for i,text in ipairs(texts) do
        if #new_rows[i]>0 then edits[i][#edits[i]+1]=Carriers.add_enums_edit(text,new_rows[i],scans[i]) end
        outputs[i]=Carriers.apply(text,edits[i])
        if outputs[i]~=text then result.changed_files[#result.changed_files+1]=Carriers.PATHS[i] end
    end
    if not opts.check then
        for i,text in ipairs(texts) do if outputs[i]~=text then deps.write_if_changed(root.."/"..Carriers.PATHS[i],outputs[i]) end end
        local summary=M.summary(result);if summary then info("[CATALOGS] "..summary) end
    end
    return result
end

function M.context_deps(C)
    return {root=C.ROOT,read=C.read_text,write_if_changed=C.write_if_changed,info=C.info,
        load=Fresh.new({root=C.ROOT,read=C.read_text}),floor=require("mvtk.core.product").property_type_id_floor,
        load_tiled_export=C.load_tiled_export, flatten_tiled_layers=C.flatten_tiled_layers,
        resolve_object_type=C.resolve_object_type, load_object_type_set=C.load_object_type_set,
        is_background_visual_object_candidate=C.is_background_visual_object_candidate,
        generated_object_id=C.generated_object_id, object_rect_center=C.object_rect_center,
        tiled_object_config=C.TILED_CONFIG, fmt_num=C.fmt_num}
end

-- Called after room collections are queued, so read sees pending resource writes.
function M.write_room_catalogs(deps, room_ids, opts)
    local ctx = {}
    for key, value in pairs(deps) do ctx[key] = value end
    ctx.root = tostring(deps.root or "."):gsub("\\", "/"):gsub("/$", "")
    ctx.info = deps.info or function() end
    ctx.load = Fresh.new({root=ctx.root, read=ctx.read})
    ctx.index = opts and opts.index or nil
    return require("mvtk.editor.room_catalogs").write(ctx, room_ids)
end

return M
