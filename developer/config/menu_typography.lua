-- Runtime menu typography and fitted geometry at 1920x1080.
-- Text uses the same generated 14 px distance-field font as the authored scenes. Scales below give nominal 16 px prompts and 18 px rows at
-- 1920x1080; Fit keeps the safe 16:9 area on other screen shapes. This is not
-- the player's Text size option (which affects reading text only).
return {
    prompt_scale = 1.142857143, -- 16 / 14, rounded upward to retain the minimum.
    row_scale = 1.285714286, -- 18 / 14; values, captions of rows and headings.
    settings = {
        focus_value_x = 340, -- Value column, relative to each preference row.
        value_width = 160, -- Physical width of runtime preference values.
        value_height = 32, -- Physical height of runtime preference values.
    },
    map = {
        legend_x = 32, -- Left edge in the safe design area.
        legend_y = 32, -- Bottom edge of the button prompt band.
        legend_width = 1856, -- Wrapped button prompts stay inside 1920 px.
        legend_height = 80, -- Room for translated, multi-line prompts.
        kinds_y = 132, -- Icon-kind labels start above the button prompt band.
        kinds_line_height = 24, -- Wrapped icon-kind row spacing.
        preview_width = 360, -- Screenshot caption and preview panel width.
        preview_caption_height = 48, -- Space below the screenshot for three nominal lines.
        palette_width = 400, -- Minimum stamp palette width, including its caption.
    },
    gallery = {
        title_y = 495, title_width = 1760, -- Heading above the image.
        caption_y = -420, caption_width = 1760, -- Caption below the image.
        help_y = -490, help_width = 1760, -- Navigation footer.
        text_height = 56, -- Physical height of each text band.
    },
    completion = {
        help_scale = 1.142857143, -- 16 px footer, independent of ending text_scale.
        width = 1440, art_text_width = 900, -- Physical body width, without/with art.
        height = 360, -- Body fits between the heading and navigation footer.
        help_width = 1760, help_height = 64, -- Footer can wrap within the safe area.
        title_height = 56, -- Heading band above the body.
        art_x = -640, -- Artwork sits to the left of the expanded body column.
    },
}
