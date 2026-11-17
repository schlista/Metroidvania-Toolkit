-- Languages supported by this game. Translation tables are generated separately.
return {
    -- Each language has a stable code, its own display name, and a plural rule:
    -- one_other (English), none (one form), or one_few_many (Slavic integers).
    languages = {
        { code = "en", name = "English", plural = "one_other" },
    },
    -- auto chooses a supported system language; a code chooses a creator default.
    default_language = "auto",
    -- Used for missing translations and unsupported system/default languages.
    fallback = "en",
    -- The player language choice is also hidden when only one language is listed.
    show_language_choice = true,
    -- Project-relative TTF/OTF used by the generated game UI and world labels.
    -- Keep the font's licence beside it; Prepare & Check checks every used glyph.
    ui_font_file = "developer/assets/fonts/DejaVuSansMono-Bold.ttf",
    -- vector (the default) draws glyph outlines, so text stays sharp at any size.
    -- It needs RGBA16F/R32UI textures: no OpenGL ES 2 or WebGL 1 devices, and no
    -- automatic fallback. distance_field runs everywhere and softens when enlarged.
    ui_text_rendering = "vector",
    -- static builds the collected letters with the game; dynamic makes them on demand.
    -- On demand bundles the font file and needs the full text layout system.
    ui_glyph_generation = "static",
}
