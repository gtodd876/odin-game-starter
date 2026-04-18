#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Screen pixels per LCD cell. Larger = chunkier "dots".
uniform float gridSize;

// 0.0 = invisible grid, 1.0 = grid lines painted fully with palette3.
uniform float gridStrength;

// DMG palette, light -> dark.
uniform vec4 palette0;
uniform vec4 palette1;
uniform vec4 palette2;
uniform vec4 palette3;

out vec4 finalColor;

vec4 quantize(vec3 rgb) {
    float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
    if (lum > 0.70) return palette0;
    if (lum > 0.45) return palette1;
    if (lum > 0.20) return palette2;
    return palette3;
}

void main() {
    vec4 src   = texture(texture0, fragTexCoord);
    vec4 quant = quantize(src.rgb);

    // Darken the last row + column of every gridSize-pixel cell so the
    // output reads like an LCD dot matrix.
    vec2  cell   = mod(gl_FragCoord.xy, gridSize);
    float gx     = step(gridSize - 1.0, cell.x);
    float gy     = step(gridSize - 1.0, cell.y);
    float onGrid = clamp(gx + gy, 0.0, 1.0);

    vec4 dmg = mix(quant, palette3, onGrid * gridStrength);
    finalColor = dmg * colDiffuse * fragColor;
}
