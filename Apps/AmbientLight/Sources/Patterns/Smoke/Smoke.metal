#include <metal_stdlib>
#include "../Shaders/ColorSpace.h"
using namespace metal;

// Simplex noise for texture replacement (prefixed to avoid symbol collision)
static float3 smoke_mod289(float3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

static float2 smoke_mod289(float2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

static float3 smoke_permute(float3 x) {
  return smoke_mod289(((x * 34.0) + 1.0) * x);
}

// 2D Simplex noise
static float smoke_snoise(float2 v) {
  const float4 C = float4(
    0.211324865405187,   // (3.0-sqrt(3.0))/6.0
    0.366025403784439,   // 0.5*(sqrt(3.0)-1.0)
    -0.577350269189626,  // -1.0 + 2.0 * C.x
    0.024390243902439    // 1.0 / 41.0
  );

  float2 i = floor(v + dot(v, C.yy));
  float2 x0 = v - i + dot(i, C.xx);

  float2 i1;
  i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);

  float4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;

  i = smoke_mod289(i);
  float3 p = smoke_permute(smoke_permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));

  float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;

  float3 x = 2.0 * fract(p * C.www) - 1.0;
  float3 h = abs(x) - 0.5;
  float3 ox = floor(x + 0.5);
  float3 a0 = x - ox;

  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

  float3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;

  return 130.0 * dot(m, g);
}

// Hash function for pseudo-random texture-like noise
static float smoke_hash(float2 p) {
  float3 p3 = fract(float3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Value noise - more similar to texture lookup
static float smoke_valueNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);

  // Smooth interpolation
  float2 u = f * f * (3.0 - 2.0 * f);

  // Four corners
  float a = smoke_hash(i);
  float b = smoke_hash(i + float2(1.0, 0.0));
  float c = smoke_hash(i + float2(0.0, 1.0));
  float d = smoke_hash(i + float2(1.0, 1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Texture-like noise with multiple frequencies
static float2 smoke_noiseTexture(float2 uv) {
  // Scale up to get more variation (like a 256x256 texture)
  float2 p = uv * 256.0;

  float n1 = smoke_valueNoise(p);
  float n2 = smoke_valueNoise(p + float2(37.0, 17.0));

  return float2(n1, n2);
}

// Smokin' shader - based on nimitz 2015
[[ stitchable ]] half4 smoke(
  float2 position,
  half4 currentColor,
  float2 size,
  float time,
  float speed,
  float density,
  float scale,
  float peakBrightness,
  float headroom,
  half4 baseColor
) {
  // Normalize to -3 to 3 range
  float4 p = float4(position, 0.0, 1.0) / float4(size, size) * 6.0 - 3.0;
  float4 z = float4(0.0);
  float4 c, d = float4(0.0);

  float t = time * speed;
  p.x -= t * 0.4;

  // Main iteration loop (matching original: for i=0 to 8, step 0.3)
  for (float i = 0.0; i < 8.0; i += 0.3) {
    // Sample noise - matching original: texture(iChannel0, p.xy*.0029)*11.
    c = float4(smoke_noiseTexture(p.xy * 0.0029 * scale) * 11.0, 0.0, 0.0);

    // Direction from noise + time - matching original
    d.x = cos(c.x + t);
    d.y = sin(c.y + t);

    // Accumulate color - matching original: (2.-abs(p.y))*vec4(.1*i, .3, .2, 9)
    z += (2.0 - abs(p.y)) * float4(0.1 * i, 0.3, 0.2, 9.0) * density;

    // Decay - matching original: dot(d,d-d+.03)+.98
    z *= dot(d.xy, d.xy - d.xy + 0.03) + 0.98;

    // Displace - matching original: p -= d*.022
    p.xy -= d.xy * 0.022;
  }

  float3 result = z.rgb / 25.0 * peakBrightness;

  // Apply base color tint
  result *= float3(baseColor.rgb);

  // Soft clipping for HDR
  float maxComponent = max(max(result.r, result.g), result.b);
  if (maxComponent > headroom * 0.8) {
    float compressionStart = headroom * 0.8;
    float compressionRange = headroom - compressionStart;
    result.r = result.r <= compressionStart ? result.r : compressionStart + compressionRange * (result.r - compressionStart) / (result.r - compressionStart + compressionRange);
    result.g = result.g <= compressionStart ? result.g : compressionStart + compressionRange * (result.g - compressionStart) / (result.g - compressionStart + compressionRange);
    result.b = result.b <= compressionStart ? result.b : compressionStart + compressionRange * (result.b - compressionStart) / (result.b - compressionStart + compressionRange);
  }

  return half4(half3(result), 1.0);
}
