-- Text-only custom-type carriers. Ranges are byte offsets in the original text.
local M = {}
M.PATHS = {
    "MVTK.tiled-project",
    "tiled/custom_types/MV_ToolKit.custom-types.json",
    "tiled/custom_types/MV_ToolKit.custom-types.array.json",
}

local escapes = { ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
local function quote(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
        for key, decoded in pairs(escapes) do
            if decoded == c and key ~= '/' then return '\\' .. key end
        end
        return string.format('\\u%04x', c:byte())
    end) .. '"'
end
M.quote = quote

-- Parse once, retaining immediate fields and ranges, never searching nested names.
local function parse(text,offset,fragment)
    local pos, size = offset or 1, #text
    local function space() local _, e = text:find('^[ \t\r\n]*', pos); pos = (e or pos-1)+1 end
    local function string_value()
        assert(text:sub(pos,pos)=='"', 'Expected JSON string')
        pos=pos+1
        local parts, start = {}, pos
        while pos<=size do
            local c=text:sub(pos,pos)
            if c=='"' then parts[#parts+1]=text:sub(start,pos-1);pos=pos+1;return table.concat(parts) end
            if c=='\\' then
                parts[#parts+1]=text:sub(start,pos-1);pos=pos+1
                local e=text:sub(pos,pos)
                if e=='u' then
                    local hex=text:sub(pos+1,pos+4);assert(hex:match('^%x%x%x%x$'),'Bad JSON escape')
                    local n=tonumber(hex,16)
                    if n<128 then parts[#parts+1]=string.char(n)
                    elseif n<2048 then parts[#parts+1]=string.char(192+math.floor(n/64),128+n%64)
                    else parts[#parts+1]=string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
                    pos=pos+4
                else parts[#parts+1]=assert(escapes[e],'Bad JSON escape') end
                start=pos+1
            end
            pos=pos+1
        end
        error('Unterminated JSON string')
    end
    local value
    value=function()
        space()
        local node={start=pos};local c=text:sub(pos,pos)
        if c=='{' or c=='[' then
            local object=c=='{';node.kind=object and 'object' or 'array'
            node.value={};node.fields={};node.items={};pos=pos+1;space()
            local close=object and '}' or ']'
            if text:sub(pos,pos)~=close then
                while true do
                    local key
                    if object then key=string_value();space();assert(text:sub(pos,pos)==':','Expected colon');pos=pos+1 end
                    local child=value()
                    if object then node.fields[key]=child;node.value[key]=child.value
                    else node.items[#node.items+1]=child;node.value[#node.value+1]=child.value end
                    space();local sep=text:sub(pos,pos)
                    if sep==close then break end
                    assert(sep==',','Expected JSON comma');pos=pos+1;space()
                end
            end
            assert(text:sub(pos,pos)==close,'Unterminated JSON container');pos=pos+1
        elseif c=='"' then node.value=string_value()
        else
            local token=text:match('^[^,%]%}%s]+',pos);assert(token,'Missing JSON value')
            if token=='true' then node.value=true elseif token=='false' then node.value=false
            elseif token~='null' then node.value=assert(tonumber(token),'Bad JSON value') end
            pos=pos+#token
        end
        node.finish=pos-1;return node
    end
    local root=value();space();assert(fragment or pos>size,'Trailing JSON bytes');return root
end

function M.property_types(text)
    if type(text)~='string' then return nil,'Missing carrier text' end
    local ok, root=pcall(parse,text)
    if not ok then return nil,'Unparsable carrier: '..tostring(root) end
    local array=root.kind=='array' and root or root.fields and root.fields.propertyTypes
    if not array then return nil,'Not a propertyTypes carrier',root end
    if array.kind~='array' then return nil,'propertyTypes must be an array' end
    local entries={array_start=array.start,array_finish=array.finish}
    for _,node in ipairs(array.items) do
        if node.kind~='object' or type(node.value.name)~='string' then return nil,'Invalid propertyTypes entry' end
        local entry=node.value
        entry.start,entry.finish,entry.fields=node.start,node.finish,node.fields
        entries[#entries+1]=entry
    end
    return entries
end

local function region(text,name,entries)
    local err,root
    if not entries then entries,err,root=M.property_types(text) end
    if entries then
        for _,entry in ipairs(entries) do
            if entry.name==name and (entry.type=='enum' or entry.type==nil) then
                if (entry.type=='enum' and entry.storageType~='string')
                    or (entry.storageType~=nil and entry.storageType~='string') then
                    return nil,'Refusing non-string enum '..name
                end
                local values=entry.fields.values
                if not values or values.kind~='array' then return nil,'Could not find '..name..' values array' end
                return values
            end
        end
        return nil,'Could not find '..name..' enum'
    end
    -- Legacy single objects and customTypes fixtures retain first-match lookup.
    if err~='Not a propertyTypes carrier' then return nil,err end
    local name_start, name_end=text:find('"name"%s*:%s*'..quote(name):gsub('(%W)','%%%1'))
    if not name_end then return nil,'Could not find '..name..' enum' end
    local function legacy_object(node)
        local field=node.fields and node.fields.name
        if field and field.start>=name_start and field.start<=name_end then return node.value end
        for _,child in pairs(node.fields or {}) do local found=legacy_object(child);if found then return found end end
        for _,child in ipairs(node.items or {}) do local found=legacy_object(child);if found then return found end end
    end
    local object=root and legacy_object(root)
    if object and object.storageType~=nil and object.storageType~='string' then
        return nil,'Refusing non-string enum '..name
    end
    local _,start=text:find('"values"%s*:%s*%[',name_end+1)
    if not start then return nil,'Could not find '..name..' values array' end
    local ok,node=pcall(parse,text,start,true)
    if not ok then return nil,'Could not find closing bracket for '..name..' values' end
    return node
end

function M.enum_values(text,name,entries)
    local node,err=region(text,name,entries)
    if not node then return nil,err end
    return node.value
end

local function indent(text,pos) return text:sub(1,pos-1):match('[\r\n]([ \t]*)[^\r\n]*$') or '' end
function M.flags_edit(text,entry,flags)
    flags=flags==true
    if entry.valuesAsFlags==flags or (entry.valuesAsFlags==nil and not flags) then return nil end
    local field=entry.fields.valuesAsFlags
    if field then return {start=field.start,finish=field.finish,text=tostring(flags)} end
    local last=entry.start
    for _,value in pairs(entry.fields) do last=math.max(last,value.finish) end
    local nl=text:find('\r\n',1,true) and '\r\n' or '\n'
    return {start=last+1,finish=last,text=','..nl..indent(text,entry.start)..'    "valuesAsFlags": '..tostring(flags)}
end

function M.values_edit(text,name,values,entries)
    local node,err=region(text,name,entries)
    if not node then return nil,err end
    local nl=text:find('\r\n',1,true) and '\r\n' or '\n'
    local close_indent=indent(text,node.finish)
    local value_indent=text:sub(node.start+1,node.finish-1):match('\n([ \t]*)"') or close_indent..'    '
    local lines={}
    for i,v in ipairs(values) do lines[i]=value_indent..quote(v)..(i<#values and ',' or '') end
    return {start=node.start,finish=node.finish,text=#lines==0 and '[]' or '['..nl..table.concat(lines,nl)..nl..close_indent..']'}
end

function M.apply(text,edits)
    table.sort(edits,function(a,b)return a.start>b.start end)
    for _,edit in ipairs(edits) do text=text:sub(1,edit.start-1)..edit.text..text:sub(edit.finish+1) end
    return text
end

function M.set_enum_values(text,name,values,entries)
    local edit,err=M.values_edit(text,name,values,entries)
    if not edit then return nil,err end
    return M.apply(text,{edit})
end

function M.max_id(texts)
    local highest=0
    for _,text in ipairs(texts) do
        local entries,err
        if type(text)=='table' then entries=text else entries,err=M.property_types(text) end
        if not entries then return nil,err end
        for _,entry in ipairs(entries) do highest=math.max(highest,tonumber(entry.id) or 0) end
    end
    return highest
end
function M.next_id(texts,floor)
    local highest,err=M.max_id(texts)
    if not highest then return nil,err end
    return math.max(highest+1,floor or 0)
end
function M.duplicate_ids(text)
    local entries,err
    if type(text)=='table' then entries=text else entries,err=M.property_types(text) end
    if not entries then return nil,err end
    local seen,duplicates={},{}
    for _,entry in ipairs(entries) do
        if seen[entry.id] then duplicates[#duplicates+1]={id=entry.id,first=seen[entry.id],second=entry.name} end
        if entry.id then seen[entry.id]=entry.name end
    end
    return duplicates
end

function M.add_enums_edit(text,rows,entries)
    if not entries then local err;entries,err=M.property_types(text);if not entries then return nil,err end end
    local last
    for _,entry in ipairs(entries) do if entry.type=='enum' then last=entry end end
    local nl=text:find('\r\n',1,true) and '\r\n' or '\n'
    local pad=indent(text,last and last.start or entries[1] and entries[1].start or entries.array_finish)..(not last and not entries[1] and '    ' or '')
    local rendered={}
    for _,row in ipairs(rows) do
        local lines={pad..'{',pad..'    "id": '..row.id..',',pad..'    "name": '..quote(row.name)..',',
            pad..'    "storageType": "string",',pad..'    "type": "enum",'}
        if #row.values==0 then lines[#lines+1]=pad..'    "values": [],'
        else
            lines[#lines+1]=pad..'    "values": ['
            for i,v in ipairs(row.values) do lines[#lines+1]=pad..'        '..quote(v)..(i<#row.values and ',' or '') end
            lines[#lines+1]=pad..'    ],'
        end
        lines[#lines+1]=pad..'    "valuesAsFlags": '..tostring(row.flags==true)
        lines[#lines+1]=pad..'}';rendered[#rendered+1]=table.concat(lines,nl)
    end
    if last then return {start=last.finish+1,finish=last.finish,text=','..nl..table.concat(rendered,','..nl)} end
    if #entries==0 then
        return {start=entries.array_start+1,finish=entries.array_finish-1,
            text=nl..table.concat(rendered,','..nl)..nl..indent(text,entries.array_finish)}
    end
    local pos=entries[1].start
    return {start=pos,finish=pos-1,text=table.concat(rendered,','..nl):sub(#pad+1)..','..nl..pad}
end
function M.add_enum(text,row)
    local edit,err=M.add_enums_edit(text,{row})
    if not edit then return nil,err end
    return M.apply(text,{edit})
end

return M
