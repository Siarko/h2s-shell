#version 440
// A wallpaper changing: `outgoing` (the image going) gives way to `incoming` as
// `progress` goes 0 → 1, the way `mode` says. Used only while a transition runs
// (wallpaper/WallpaperSurface.qml); the image is drawn plainly before and after.
// Compiled with: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o transition.frag.qsb transition.frag
//
// mode: 0 wipe (a soft edge sweeping left to right, slightly slanted), 1 circle (growing
// from the middle), 2 dissolve (blocks changing in a random order), 3 pixelate (the old
// image breaks into large pixels, the new one forms from them)

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    // width / height of the screen, and its size in pixels
    float aspect;
    vec2 size;
    // How soft an edge is, in the 0–1 of the screen
    float softness;
};

layout(binding = 1) uniform sampler2D outgoing;
layout(binding = 2) uniform sampler2D incoming;

float hash(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

// 0 → 1 as `t` passes `value`, over a soft band of `softness` either side; at t = 0 nothing
// has passed, at t = 1 everything in [0, 1] has
float sweep(float value, float t) {
    float position = t * (1.0 + 2.0 * softness) - softness;
    return 1.0 - smoothstep(position - softness, position + softness, value);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float t = clamp(progress, 0.0, 1.0);
    vec4 going = texture(outgoing, uv);
    vec4 coming = texture(incoming, uv);
    float mixAmount = 0.0;

    if (mode < 0.5) {
        mixAmount = sweep(uv.x * 0.85 + uv.y * 0.15, t);
    } else if (mode < 1.5) {
        vec2 offset = (uv - vec2(0.5)) * vec2(aspect, 1.0);
        float reach = length(vec2(0.5 * aspect, 0.5));
        mixAmount = sweep(length(offset) / reach, t);
    } else if (mode < 2.5) {
        float noise = hash(floor(uv * vec2(aspect, 1.0) * 90.0));
        mixAmount = sweep(noise, t);
    } else {
        // Pixels grow to the middle of the transition and shrink after it
        float coarse = 1.0 - abs(t * 2.0 - 1.0);
        float cell = max(1.0, coarse * 64.0);
        vec2 cells = size / cell;
        vec2 snapped = (floor(uv * cells) + 0.5) / cells;
        going = texture(outgoing, snapped);
        coming = texture(incoming, snapped);
        mixAmount = smoothstep(0.4, 0.6, t);
    }

    fragColor = mix(going, coming, mixAmount) * qt_Opacity;
}
