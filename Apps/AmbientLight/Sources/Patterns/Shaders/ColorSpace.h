#ifndef ColorSpace_h
#define ColorSpace_h

#include <metal_stdlib>
using namespace metal;

// ==========================================
// 共通カラーレンジ: 50°〜310°
// 黄色〜オレンジ〜赤〜マゼンタ〜紫
// ==========================================

constant float COLOR_RANGE_MIN_HUE = 50.0 / 360.0;   // 0.139
constant float COLOR_RANGE_MAX_HUE = 310.0 / 360.0;  // 0.861
constant float COLOR_RANGE_HUE_SPAN = COLOR_RANGE_MAX_HUE - COLOR_RANGE_MIN_HUE;

// 0〜1の値を許可された色相範囲にマッピング
static inline float mapToAllowedHue(float value) {
  return COLOR_RANGE_MIN_HUE + value * COLOR_RANGE_HUE_SPAN;
}

// 色相を許可範囲にクランプ
static inline float clampToAllowedHue(float hue) {
  return clamp(hue, COLOR_RANGE_MIN_HUE, COLOR_RANGE_MAX_HUE);
}

// ==========================================
// HSV <-> RGB 変換
// ==========================================

// HSV to RGB (h: 0-1, s: 0-1, v: 0-1)
static inline float3 hsv2rgb(float3 c) {
  float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// RGB to HSV
static inline float3 rgb2hsv(float3 c) {
  float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
  float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// ==========================================
// 許可範囲内のカラー生成
// ==========================================

// 許可範囲内の色相でHSV→RGBカラーを生成
// hueValue: 0〜1（自動的に50°〜310°にマッピング）
static inline float3 allowedHueColor(float hueValue, float saturation, float value) {
  float hue = mapToAllowedHue(hueValue);
  return hsv2rgb(float3(hue, saturation, value));
}

// RGBカラーの色相を許可範囲にクランプ
static inline float3 clampColorHue(float3 rgb) {
  float3 hsvColor = rgb2hsv(rgb);
  hsvColor.x = clampToAllowedHue(hsvColor.x);
  return hsv2rgb(hsvColor);
}

// ==========================================
// OKLAB / OKLCH 色空間
// ==========================================

// Linear sRGB to OKLAB
static inline float3 srgbToOklab(float3 c) {
  // sRGB to linear
  float3 linear = pow(max(c, 0.0), 3.0);

  float l = 0.4122214708 * linear.r + 0.5363325363 * linear.g + 0.0514459929 * linear.b;
  float m = 0.2119034982 * linear.r + 0.6806995451 * linear.g + 0.1073969566 * linear.b;
  float s = 0.0883024619 * linear.r + 0.2817188376 * linear.g + 0.6299787005 * linear.b;

  float l_ = pow(l, 1.0/3.0);
  float m_ = pow(m, 1.0/3.0);
  float s_ = pow(s, 1.0/3.0);

  return float3(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  );
}

// OKLAB to sRGB
static inline float3 oklabToSrgb(float3 lab) {
  float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
  float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
  float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;

  float l = l_ * l_ * l_;
  float m = m_ * m_ * m_;
  float s = s_ * s_ * s_;

  float3 linear = float3(
    +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  );

  // Linear to sRGB
  return pow(max(linear, 0.0), 1.0/3.0);
}

// sRGB to OKLCH
static inline float3 srgbToOklch(float3 c) {
  float3 lab = srgbToOklab(c);
  float C = sqrt(lab.y * lab.y + lab.z * lab.z);
  float H = atan2(lab.z, lab.y);
  if (H < 0.0) H += 2.0 * M_PI_F;
  return float3(lab.x, C, H / (2.0 * M_PI_F));  // H normalized to 0-1
}

// OKLCH to sRGB
static inline float3 oklchToSrgb(float3 lch) {
  float H = lch.z * 2.0 * M_PI_F;  // H from 0-1 to radians
  float3 lab = float3(lch.x, lch.y * cos(H), lch.y * sin(H));
  return oklabToSrgb(lab);
}

// Interpolate hue taking shortest path
static inline float interpolateHue(float h1, float h2, float t) {
  float diff = h2 - h1;
  if (diff > 0.5) diff -= 1.0;
  if (diff < -0.5) diff += 1.0;
  float result = h1 + diff * t;
  if (result < 0.0) result += 1.0;
  if (result > 1.0) result -= 1.0;
  return result;
}

#endif /* ColorSpace_h */
