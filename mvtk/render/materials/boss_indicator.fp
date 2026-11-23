#version 140

in mediump vec2 var_texcoord0;
out vec4 out_fragColor;

uniform mediump sampler2D texture_sampler;
uniform fs_uniforms
{
    mediump vec4 tint;
    mediump vec4 indicator_opacity;
};

void main()
{
    // The white artwork encodes fill at 51/255 and rim at 1 in alpha.
    // The last two channels give the artwork's fill and flat-coverage mode.
    float mask = texture(texture_sampler, var_texcoord0).a;
    float baked_fill = indicator_opacity.z;
    float coverage = clamp(mask / max(baked_fill, 0.001), 0.0, 1.0);
    float rim = (mask - coverage * baked_fill) / (1.0 - baked_fill);
    float filled = mix(indicator_opacity.x, indicator_opacity.y, rim) * coverage;
    // "flat" is a reserved word in GLSL (an interpolation qualifier): Bob refuses it.
    float even = min(indicator_opacity.x, indicator_opacity.y) * coverage;
    float opacity = baked_fill > 0.0 ? mix(filled, even, indicator_opacity.w)
                                    : mask * indicator_opacity.y;
    float alpha = tint.a * opacity;
    out_fragColor = vec4(tint.rgb * alpha, alpha);
}
