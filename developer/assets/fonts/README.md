# Fonts

`fredoka.font` is the label font for the Layout Editor's room names and the
progression panel (GUI font name `room_label`). Creator tools and the debug
overlay keep their existing fonts.

`Fredoka-Medium.ttf` is Fredoka by Milena Brandão and Hafontia, licensed under
the SIL Open Font License 1.1 (`Fredoka-OFL.txt`). It is a static instance of
the variable `Fredoka[wdth,wght].ttf` from Google Fonts
(https://github.com/google/fonts/tree/main/ofl/fredoka), made with the
fontTools instancer at `wdth=90`, `wght=500`, so its text width and stroke
weight match the previous label font.

Keep `Fredoka-OFL.txt` next to the font file. To use another font, add its
`.ttf` or `.otf` here with its license and change `font:` in `fredoka.font`.

`ui_text.font` is the generated game GUI font. `ui_label.font` uses the same
face, nominal size 14 and collected letters with the matching label material for
world labels. Prepare & Check rebuilds both from printable ASCII, English UI
wording, collected creator text and the manifest-listed translation tables.
Game Settings ▸ Languages ▸ UI font file selects a project `.ttf` or `.otf`.
Keep that file's licence beside it. **Text rendering** chooses **Vector** (the
default) or **Distance field**. Vector stays sharp at any size, but needs RGBA16F
and R32UI textures: OpenGL ES 2 and WebGL 1 devices cannot use it, and there is
no automatic fallback. Exclude GLES 2.0 when building a Vector project, or choose
Distance field, which runs everywhere and softens when text is enlarged.

**Glyph generation** chooses **Built with the game** (the default) or **On demand**.
On demand bundles the font file and needs the full text layout system. Prepare &
Check updates and selects the toolkit's `game.appmanifest`, retaining its physics
and other library choices. A different selected manifest must already enable
**Use full text layout system**; preparation refuses to edit it. Only platforms
already in the manifest are updated. Refresh your native engine after changing
this configuration; recorded verification caches cover only the baseline.
Switching back to Built with the game, including Reset Project, leaves the
selected full-layout engine in place and restores static fonts. Export Game
preserves the source project's manifest selection.

All generated-font GUI text and labels carry Font Size 14. SDF uses the font
resource's size; Vector uses the component/node value. Runtime text clones the
disabled, empty `generated_text_template` in its host scene; keep that node.
The shared size lives in `mvtk/ui/generated_text.lua`. GUI scenes use the font
material; Prepare & Check switches label materials before baking room prototypes.
Fredoka and creator tools keep their existing appearance. Static Vector's engine
requirements and rendering await native 1.14.1 verification.

The default is **DejaVu Sans Mono Bold 2.37**, a free extension of Bitstream
Vera Sans Mono Bold. `DejaVuSansMono-Bold.ttf` and `DejaVu-LICENSE.txt` were
extracted unchanged from the [official DejaVu 2.37 release](https://github.com/dejavu-fonts/dejavu-fonts/releases/tag/version_2_37),
asset [dejavu-fonts-ttf-2.37.zip](https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip).

SHA-256:

- Release archive: `7576310b219e04159d35ff61dd4a4ec4cdba4f35c00e002a136f00e96a908b0a`
- `DejaVuSansMono-Bold.ttf`: `bce60f1b4421acd9ea51ba6623d7024ecbe6817a953e3654df62a5e6bdf8f769`
- `DejaVu-LICENSE.txt`: `7a083b136e64d064794c3419751e5c7dd10d2f64c108fe5ba161eae5e5958a93`

Accented Latin, Greek and Cyrillic are covered by this face. For CJK, add a
suitably licensed creator font. Prepare & Check refuses missing glyphs and
names the language, code point and sample text; it never silently substitutes
a different font.
