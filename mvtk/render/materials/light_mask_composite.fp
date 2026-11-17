#version 140
in mediump vec2 var_uv;
out vec4 color_out;
uniform sampler2D light_mask;
void main() {
    color_out = vec4(texture(light_mask, var_uv).rgb, 1.0);
}
