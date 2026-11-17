#version 140
in mediump vec2 var_uv;
out vec4 color_out;
uniform sampler2D texture_sampler;
uniform fs_uniforms {
    lowp vec4 tint;
    mediump vec4 light_params;
};
void main() {
    color_out = vec4(tint.rgb * tint.a * pow(texture(texture_sampler, var_uv).a, max(light_params.x, 0.01)), 1.0);
}
