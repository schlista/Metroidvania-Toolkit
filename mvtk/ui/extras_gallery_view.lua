local GeneratedText = require "mvtk.ui.generated_text"
-- Full-screen Extras gallery viewer, drawn by the Extras host scene
-- (developer/ui/menus/extras_viewer.gui, texture "gallery"). Left and right
-- page through the unlocked images, Back closes. Five nodes at most: the
-- covered backdrop, the image, its title, its caption and the button help.
local Viewport = require "mvtk.ui.viewport"
local DisplayText = require "mvtk.ui.display_text"
local InputPrompts = require "mvtk.ui.input_prompts"
local Typography = require "developer.config.menu_typography"
local Layout = Typography.gallery
local M = {}

-- The area the image fits in, in design pixels, and its centre above the middle.
M.MAX_WIDTH, M.MAX_HEIGHT, M.IMAGE_Y = 1600, 820, 40
M.TEXTURE = "gallery"

-- Whole-pixel size that fits width x height inside max_w x max_h, keeping the
-- shape. Small images scale up to fill the area.
function M.fit(width, height, max_w, max_h)
    width, height = math.floor(tonumber(width) or 0), math.floor(tonumber(height) or 0)
    max_w, max_h = max_w or M.MAX_WIDTH, max_h or M.MAX_HEIGHT
    if width <= 0 or height <= 0 then return 0, 0 end
    if width * max_h >= height * max_w then
        return max_w, math.max(1, math.floor((height * max_w + math.floor(width / 2)) / width))
    end
    return math.max(1, math.floor((width * max_h + math.floor(height / 2)) / height)), max_h
end

local function clear(s) if s.root then gui.delete_node(s.root); s.root = nil end end
local function text(s, y, value, scale, width)
    local n = GeneratedText.new(gui, "/developer/ui/menus/extras_viewer.gui", vmath.vector3(0, y, 0), value)
    gui.set_parent(n, s.root, false); gui.set_font(n, "default")
    gui.set_scale(n, vmath.vector3(scale, scale, 1)); gui.set_size(n, vmath.vector3(width / scale, Layout.text_height / scale, 0))
    gui.set_line_break(n, true)
    return n
end
local function draw(s)
    clear(s)
    local entry = s.images[s.index]
    local w, h = Viewport.design_size()
    s.root = gui.new_box_node(vmath.vector3(w / 2, h / 2, 0), vmath.vector3(w, h, 0))
    Viewport.cover(s.root)
    s.view_revision = Viewport.revision()
    gui.set_color(s.root, vmath.vector4(0.02, 0.02, 0.03, 1))
    local fw, fh = M.fit(entry.width, entry.height)
    local image = gui.new_box_node(vmath.vector3(0, M.IMAGE_Y, 0), vmath.vector3(fw, fh, 0))
    gui.set_parent(image, s.root, false)
    gui.set_texture(image, M.TEXTURE)
    gui.play_flipbook(image, entry.image)
    gui.set_size_mode(image, gui.SIZE_MODE_MANUAL)
    gui.set_size(image, vmath.vector3(fw, fh, 0))
    local title = type(entry.title) == "string" and entry.title:find("%S") and entry.title or nil
    text(s, Layout.title_y, title and DisplayText.render(title) or DisplayText.ui("list.missing_name"), Typography.row_scale, Layout.title_width)
    local caption = type(entry.caption) == "string" and entry.caption:find("%S") and DisplayText.render(entry.caption) or ""
    text(s, Layout.caption_y, caption, Typography.prompt_scale, Layout.caption_width)
    local parts = {}
    if #s.images > 1 then
        parts[#parts + 1] = { key = "key_left", pad = "gamepad_lpad_left", text_key = "completion.previous" }
        parts[#parts + 1] = { key = "key_right", pad = "gamepad_lpad_right", text_key = "extras.next" }
    end
    parts[#parts + 1] = { command = "back", text_key = "extras.close" }
    text(s, Layout.help_y, DisplayText.legend(parts, { separator = "     " }), Typography.prompt_scale, Layout.help_width)
    s.prompt_revision = DisplayText.revision()
end

-- images: the provider's viewable list; index: the one to show first.
-- opts.close runs after the viewer closes. Returns nil when there is nothing to show.
function M.open(images, index, opts)
    if type(images) ~= "table" or #images == 0 then return nil end
    opts = opts or {}
    local s = { images = images, index = math.max(1, math.min(#images, math.floor(tonumber(index) or 1))),
        close = opts.close }
    draw(s)
    return s
end
function M.update(s)
    if s.prompt_revision ~= DisplayText.revision() then draw(s) end
    local revision = Viewport.revision()
    if s.view_revision ~= revision then
        Viewport.cover(s.root)
        s.view_revision = revision
    end
end
function M.close(s) clear(s); if s.close then s.close() end end
-- Moves by step through the images, wrapping at either end.
function M.move(s, step)
    local count = #s.images
    if count < 2 then return end
    s.index = (s.index - 1 + step) % count + 1
    draw(s)
end
function M.input(s, id, action)
    if not action.pressed then return true end
    if InputPrompts.menu_matches("back", id) or InputPrompts.menu_matches("confirm", id) then M.close(s)
    elseif id == hash("key_left") or id == hash("gamepad_lpad_left") then M.move(s, -1)
    elseif id == hash("key_right") or id == hash("gamepad_lpad_right") then M.move(s, 1) end
    return true
end
return M
