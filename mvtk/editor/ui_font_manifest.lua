-- Conservative, line-preserving app-manifest edits. Only the toolkit's YAML
-- subset is editable: mappings and one-line scalar lists. Refuse other YAML
-- rather than flattening a creator's custom engine configuration.
local M = {}
local function trim(s) return s:match("^%s*(.-)%s*$") end
local function list(value)
    local inside = assert(value:match("^%[(.*)%]$"), "Expected a one-line manifest list")
    local set, values = {}, {}
    for token in inside:gmatch("[^,]+") do
        token = trim(token)
        assert(token:match("^[%w_.+-]+$"), "Unsupported manifest list member")
        assert(not set[token], "Duplicate manifest list member: " .. token)
        set[token] = true; values[#values+1] = token
    end
    return set, values
end

function M.parse(text)
    assert(type(text)=="string", "App manifest is missing")
    local doc = {platforms={},lines={}}
    local platform, context, root_seen
    for raw in (text .. (text:sub(-1)=="\n" and "" or "\n")):gmatch("([^\n]*)\n") do
        raw=raw:gsub("\r$","");doc.lines[#doc.lines+1]=raw
        local clean=raw:gsub("%s+#.*$","")
        if not clean:match("^%s*#") and not clean:match("^%s*$") then
            assert(not clean:find("\t",1,true), "Manifest indentation must use spaces")
            if clean=="platforms:" then assert(not root_seen,"Duplicate platforms mapping");root_seen=true
            elseif clean:match("^  [%w_-]+:$") then
                assert(root_seen,"Missing platforms mapping")
                local name=clean:match("^  (.-):$")
                for _,p in ipairs(doc.platforms)do assert(p.name~=name,"Duplicate manifest platform")end
                platform={name=name,context={},fields={}};doc.platforms[#doc.platforms+1]=platform;context=false
            elseif clean=="    context:" then
                assert(platform and not platform.context_line,"Duplicate or misplaced manifest context")
                context=true;platform.context_line=#doc.lines
            else
                assert(platform and context,"Unsupported app manifest structure")
                local key,value=clean:match("^      ([%w_-]+):%s*(.-)%s*$")
                assert(key and not platform.fields[key],"Unsupported or duplicate manifest field")
                local field={line=#doc.lines,value=value};platform.fields[key]=field
                if value:sub(1,1)=="[" then field.set,field.values=list(value);platform.context[key]=field.set
                else assert(value:match("^[%w_.+-]+$"),"Unsupported manifest scalar") end
            end
        end
    end
    assert(root_seen and #doc.platforms>0,"App manifest has no platforms")
    for _,p in ipairs(doc.platforms)do assert(p.context_line,"Manifest platform has no context")end
    return doc
end

local function libraries(platform)
    return platform=="x86_64-win32"
        and {"font_skribidi","libharfbuzz","libsheenbidi","libunibreak","libskribidi"}
        or {"font_skribidi","harfbuzz","sheenbidi","unibreak","skribidi"}
end
function M.full_layout(doc)
    for _,p in ipairs(doc.platforms)do
        if not (p.context.excludeLibs or {}).font then return false end
        for _,name in ipairs(libraries(p.name))do if not (p.context.libs or {})[name]then return false end end
    end
    return true
end
function M.enable(text)
    local doc=M.parse(text);if M.full_layout(doc)then return text end
    local inserts={}
    for _,p in ipairs(doc.platforms)do
        for _,spec in ipairs({{key="excludeLibs",names={"font"}},{key="libs",names=libraries(p.name)}})do
            local field=p.fields[spec.key]
            assert(not field or field.values,"Manifest engine libraries must be lists")
            local values,set={},{}
            for _,v in ipairs(field and field.values or {})do values[#values+1]=v;set[v]=true end
            for _,v in ipairs(spec.names)do if not set[v]then values[#values+1]=v;set[v]=true end end
            local line="      "..spec.key..": ["..table.concat(values,", ").."]"
            if field then
                local comment=doc.lines[field.line]:match("(%s+#.*)$") or ""
                doc.lines[field.line]=line..comment
            else inserts[p.context_line]=(inserts[p.context_line] or "")..line.."\n" end
        end
    end
    local out={}
    for i,line in ipairs(doc.lines)do out[#out+1]=line.."\n";if inserts[i]then out[#out+1]=inserts[i]end end
    return table.concat(out)
end

local function project_manifest(project)
    local doc={lines={}}
    local section,count,sections=nil,0,0
    for line in (project..(project:sub(-1)=="\n" and "" or "\n")):gmatch("([^\n]*)\n")do
        doc.lines[#doc.lines+1]=line
        local clean=line:gsub("\r$","")
        local heading=clean:match("^%s*%[([^%]]+)%]%s*$")
        if heading then
            section=heading
            if section=="native_extension"then sections=sections+1;doc.heading=#doc.lines end
        end
        if section=="native_extension" then
            local value=clean:match("^%s*app_manifest%s*=%s*(.-)%s*$")
            if value then count=count+1;doc.selection=value~="" and value or nil;doc.assignment=#doc.lines end
        end
    end
    assert(count<=1 and sections<=1,"On demand: game.project has duplicate app manifest selections")
    return doc
end
function M.selection(project)return project_manifest(project).selection end
function M.plan(root,read)
    local project=assert(read(root.."/game.project"),"On demand needs game.project")
    local doc=project_manifest(project);local selection=doc.selection
    if selection and selection~="/game.appmanifest" then
        assert(selection:match("^/[%w_./-]+%.appmanifest$") and not selection:find("..",1,true),"On demand: unsafe app manifest path")
        local ok,doc=pcall(M.parse,read(root..selection))
        assert(ok and M.full_layout(doc),"On demand needs the full text layout system in "..selection..". Enable Use full text layout system there, or select the toolkit's /game.appmanifest under Native Extensions.")
        return {}
    end
    local manifest=read(root.."/game.appmanifest")
    local ok,content=pcall(M.enable,manifest)
    assert(ok,"On demand cannot safely edit /game.appmanifest: "..tostring(content)..". Use the editor's Use full text layout system option in an app manifest selected under Native Extensions.")
    local files={}
    if content~=manifest then files[#files+1]={path="game.appmanifest",content=content}end
    if not selection then
        local newline=project:find("\r\n",1,true) and "\r\n" or "\n"
        if doc.assignment then doc.lines[doc.assignment]="app_manifest = /game.appmanifest"..(newline=="\r\n" and "\r" or "")
        elseif doc.heading then table.insert(doc.lines,doc.heading+1,"app_manifest = /game.appmanifest"..(newline=="\r\n" and "\r" or ""))
        else doc.lines[#doc.lines+1]="[native_extension]"..(newline=="\r\n" and "\r" or "");doc.lines[#doc.lines+1]="app_manifest = /game.appmanifest"..(newline=="\r\n" and "\r" or "")end
        project=table.concat(doc.lines,"\n").."\n"
        files[#files+1]={path="game.project",content=project}
    end
    return files
end
return M
