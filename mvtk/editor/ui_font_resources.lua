-- Synchronize authored label materials before room prototypes are content-hashed.
local R = require "mvtk.editor.resource_text"
local M = {}
M.authored_labels = {"developer/game/fx/damage_number.label", "developer/game/prefabs/npc_bubble.label",
    "developer/game/prefabs/door_unlock_test.go"}

function M.material(mode) return "/builtins/fonts/label-"..(mode=="vector" and "vector" or "df")..".material" end
function M.rewrite(text, extension, mode)
    local doc=R.parse(text)
    if extension=="label" then
        if R.value(doc.root,"font")=="/developer/assets/fonts/ui_label.font" then
            local field=R.one(doc.root,"material")
            if field then if field.value~=M.material(mode)then R.replace(doc,field,M.material(mode))end
            else R.insert(doc,doc.root,'material: "'..M.material(mode)..'"')end
        end
    else
        local group=extension=="collection" and "embedded_instances" or "embedded_components"
        for _,field in ipairs(R.all(doc.root,group))do
            local kind=extension=="collection" and "go" or R.value(field.node,"type")
            if kind=="go" or kind=="label" then
                local data=R.one(field.node,"data")
                if data then local updated=M.rewrite(data.value,kind,mode);if updated~=data.value then R.replace(doc,data,updated)end end
            end
        end
    end
    return R.render(doc)
end
function M.plan(opts,mode)
    local root,read=opts.root or ".",opts.read or require("mvtk.editor.project_transaction").read
    local paths={}
    if opts.list_dir_filesystem then
        local function visit(path)
            if path=="developer/rooms/generated" or path=="developer/rooms/collections" or path=="developer/assets/tiled" then return end
            local dirs,files=opts.list_dir_filesystem(root.."/"..path)
            for _,name in ipairs(files or {})do
                if name:match("%.label$") or name:match("%.go$") or name:match("%.collection$")then paths[#paths+1]=path.."/"..name end
            end
            for _,name in ipairs(dirs or {})do visit(path.."/"..name)end
        end
        visit("developer");visit("mvtk")
    else for _,path in ipairs(M.authored_labels)do paths[#paths+1]=path end end
    table.sort(paths)
    local out={}
    for _,path in ipairs(paths)do
        local text=read(root.."/"..path)
        if text and text:find("ui_label.font",1,true)then
            local updated=M.rewrite(text,path:match("%.(%w+)$"),mode)
            if updated~=text then out[#out+1]={path=path,content=updated}end
        end
    end
    return out
end
return M
