#version 140
in vec2 var_uv;
out vec4 color_out;
uniform sampler2D scene;
uniform fs_uniforms {
    vec4 tone;
    vec4 tint;
    vec4 crt;
};
void main() {
    vec2 p = var_uv * 2.0 - 1.0;
    vec2 uv = (p * (1.0 + crt.z * dot(p, p))) * 0.5 + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
        color_out = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    vec3 c = texture(scene, uv).rgb;
    c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, tone.z);
    c = mix(c, c * tint.rgb, tint.a);
    c = pow(max(c * tone.x, vec3(0.0)), vec3(tone.y));
    c *= 1.0 - crt.x * (0.5 - 0.5 * cos(uv.y * crt.y * 6.28318530718));
    c *= 1.0 - crt.w * clamp(dot(p, p) * 0.5, 0.0, 1.0);
    color_out = vec4(c, 1.0);
}
