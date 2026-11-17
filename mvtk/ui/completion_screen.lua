local GeneratedText = require "mvtk.ui.generated_text"
local Viewport = require "mvtk.ui.viewport"
local Pages = require "mvtk.ui.completion_pages"
local InputPrompts = require "mvtk.ui.input_prompts"
local DisplayText = require "mvtk.ui.display_text"
local Localization = require "mvtk.core.localization"
-- Only known friendly failure sources may appear in the player presentation.
-- Arbitrary persistence codes/exceptions stay in s.error for diagnostics/retry.
local save_error_keys = {["Disk full"]="completion.error.disk_full"}
-- Shared runtime/temporary-preview presentation; this module never saves state.
local Typography = require "developer.config.menu_typography"
local Layout = Typography.completion
local M={}
local function clear(s) if s.root then gui.delete_node(s.root); s.root=nil end end
local function text(s,x,y,value,scale,width,rendered)
    local n=GeneratedText.new(gui, s._generated_text_scene or "/developer/ui/game/completion.gui", vmath.vector3(x,y,0),rendered and value or DisplayText.render(value))
    gui.set_parent(n,s.root,false); gui.set_font(n,s.font)
    gui.set_scale(n,vmath.vector3(scale,scale,1)); gui.set_size(n,vmath.vector3((width or Layout.width) / scale, Layout.height / scale,0))
    gui.set_line_break(n,true); return n
end
local function draw(s)
    clear(s)
    local metadata
    s.content,metadata=Pages.build(s.cfg,s.data,{render=DisplayText.render,ui=DisplayText.ui,plural_form=Localization.plural_form,
        assist_used=not s.preview and require("mvtk.player.assist").record_use() and require("mvtk.core.flags").has("assist_used")})
    s.credits,s.per_page=metadata.credits,metadata.per_page
    s.pages=#s.content-1
    s.page=math.max(0,math.min(s.page,s.pages))
    local w,h=Viewport.design_size()
    s.root=gui.new_box_node(vmath.vector3(w/2,h/2,0),vmath.vector3(w,h,0))
    Viewport.cover(s.root)
    s.view_revision=Viewport.revision()
    gui.set_color(s.root,vmath.vector4(0.025,0.035,0.06,1))
    local page=s.content[s.page+1]
    local title,body=page.title,page.body
    if s.error then
        title=DisplayText.ui("completion.save_failed")
        local key=save_error_keys[s.error]
        body=key and DisplayText.ui("completion.save_failed_body",{error=DisplayText.ui(key)})
            or DisplayText.ui("completion.save_failed_fallback")
    end
    local has_art=s.cfg.artwork~="" and not s.error and s.page==0 and s.artwork
    if has_art then
        local art=gui.new_box_node(vmath.vector3(Layout.art_x,0,0),vmath.vector3(220,180,0))
        gui.set_parent(art,s.root,false); gui.set_texture(art,"artwork"); gui.play_flipbook(art,s.cfg.artwork)
    end
    -- Older ending configs used sub-unit scales; retain a readable minimum.
    local scale=math.max(Typography.row_scale,s.cfg.text_scale or Typography.row_scale)
    local heading=text(s,0,210,title,scale,nil,true)
    gui.set_size(heading,vmath.vector3(Layout.width / scale,Layout.title_height / scale,0))
    text(s,has_art and 130 or 0,-20,body,scale,has_art and Layout.art_text_width or Layout.width,true)
    local parts
    if s.error then
        parts={{command="confirm",text_key="completion.retry"},{command="back",text_key="completion.keep_playing"}}
    else
        parts={{command="confirm",text_key=s.page<s.pages and "completion.next" or "completion.return",
            key=s.page<s.pages and "key_right" or nil,pad=s.page<s.pages and "gamepad_lpad_right" or nil},
            {key="key_left",pad="gamepad_lpad_left",text_key="completion.previous"},
            {command="back",text_key=s.preview and "completion.close_preview" or "completion.return"}}
    end
    local help=DisplayText.legend(parts,{separator="     "})
    local footer=text(s,0,-230,help,Layout.help_scale,Layout.help_width,true)
    gui.set_size(footer,vmath.vector3(Layout.help_width / Layout.help_scale,Layout.help_height / Layout.help_scale,0))
    s.prompt_revision=DisplayText.revision()
end
function M.open(cfg,data,opts)
    opts=opts or {}; local s={cfg=cfg,data=data or {},font=opts.font or cfg.font or "default",page=0,
        _generated_text_scene=opts.scene,error=opts.error,preview=opts.preview,artwork=opts.artwork,close=opts.close,retry=opts.retry,credits={}}
    draw(s); return s
end
function M.update(s)
    if s.prompt_revision~=DisplayText.revision() then draw(s) end
    local revision=Viewport.revision()
    if s.view_revision~=revision then
        Viewport.cover(s.root)
        s.view_revision=revision
    end
end
function M.close(s) clear(s); if s.close then s.close() end end
function M.input(s,id,action)
    if s.prompt_revision~=DisplayText.revision() then draw(s) end
    if not action.pressed then return true end
    if InputPrompts.menu_matches("back", id) then M.close(s)
    elseif id==hash("key_left") or id==hash("gamepad_lpad_left") then s.page=math.max(0,s.page-1); draw(s)
    elseif InputPrompts.menu_matches("confirm", id) or id==hash("key_right") or id==hash("gamepad_lpad_right") then
        if s.error then clear(s); if s.retry then s.retry() end
        elseif s.page>=s.pages then M.close(s)
        else s.page=s.page+1; draw(s) end
    end
    return true
end
return M
