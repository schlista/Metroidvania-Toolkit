#version 140
in vec2 var_uv;
out vec4 color_out;
uniform sampler2D scene;
// Placeholder passthrough; fullscreen passes always override this material.
void main() {
    color_out = texture(scene, var_uv);
}
