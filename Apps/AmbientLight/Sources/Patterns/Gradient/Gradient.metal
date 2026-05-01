#include <metal_stdlib>
#include "../Shaders/ColorSpace.h"
using namespace metal;

// =============================================================================
// MARK: - Gradient Helpers
// =============================================================================

/// Find which color stops the given position falls between
/// Returns index of the lower stop (0-2 for 4 stops)
int findColorStopSegment(float t, float4 stops) {
  if (t <= stops.x) return 0;
  if (t <= stops.y) return 1;
  if (t <= stops.z) return 2;
  return 3;
}

/// Calculate local interpolation factor between two stops
float getLocalT(float t, float stop1, float stop2) {
  if (stop2 <= stop1) return 0.0;
  return clamp((t - stop1) / (stop2 - stop1), 0.0, 1.0);
}

/// Interpolate colors in sRGB space
float3 interpolateSRGB(float3 color1, float3 color2, float t) {
  return mix(color1, color2, t);
}

/// Interpolate colors in OKLAB space
float3 interpolateOKLAB(float3 color1, float3 color2, float t) {
  float3 oklab1 = srgbToOklab(color1);
  float3 oklab2 = srgbToOklab(color2);
  float3 mixed = mix(oklab1, oklab2, t);
  return oklabToSrgb(mixed);
}

/// Interpolate colors in OKLCH space (with hue interpolation)
float3 interpolateOKLCH(float3 color1, float3 color2, float t) {
  float3 oklch1 = srgbToOklch(color1);
  float3 oklch2 = srgbToOklch(color2);

  // Interpolate L and C linearly
  float L = mix(oklch1.x, oklch2.x, t);
  float C = mix(oklch1.y, oklch2.y, t);

  // Interpolate H using shortest path
  float H = interpolateHue(oklch1.z, oklch2.z, t);

  float3 mixed = float3(L, C, H);
  return oklchToSrgb(mixed);
}

// =============================================================================
// MARK: - Main Shader
// =============================================================================

/// SwiftUI用のグラデーションシェーダー（HDR対応）
[[ stitchable ]] half4 gradient(
  float2 position,
  half4 currentColor,
  float2 size,
  float time,
  float angle,           // グラデーション角度（0〜360度）
  float colorSpace,      // 0=sRGB, 1=OKLAB, 2=OKLCH
  float gradientType,    // 0=linear, 1=radial
  half4 color1,          // カラーストップ1（HDR）
  half4 color2,          // カラーストップ2（HDR）
  half4 color3,          // カラーストップ3（HDR）
  half4 color4,          // カラーストップ4（HDR）
  float stop1,           // ストップ位置1 (0.0〜1.0)
  float stop2,           // ストップ位置2
  float stop3,           // ストップ位置3
  float stop4,           // ストップ位置4
  float peakBrightness,  // HDR輝度倍率
  float headroom,        // HDR headroom（最大輝度制限、1.0〜8.0）
  float animate          // アニメーション強度（0.0 = なし）
) {
  // 正規化座標（0〜1）
  float2 uv = position / size;

  // パラメータをintにキャスト
  int colorSpaceInt = int(colorSpace);
  int gradientTypeInt = int(gradientType);

  // グラデーション位置の計算
  float t = 0.0;

  if (gradientTypeInt == 0) {
    // Linear gradient
    // 角度をラジアンに変換（-90度オフセットで上が0度）
    float rad = (angle - 90.0) * M_PI_F / 180.0;

    // 回転行列を適用
    float2 dir = float2(cos(rad), sin(rad));

    // 中心からの距離を計算
    float2 centered = uv - 0.5;
    t = dot(centered, dir) + 0.5;

    // アニメーション（時間で位置を変化）
    if (animate > 0.0) {
      t += sin(time * animate * 0.5) * 0.1;
    }

  } else if (gradientTypeInt == 1) {
    // Radial gradient
    float2 center = float2(0.5, 0.5);

    // アニメーション（中心位置を動かす）
    if (animate > 0.0) {
      center.x += sin(time * animate * 0.3) * 0.1;
      center.y += cos(time * animate * 0.4) * 0.1;
    }

    float dist = distance(uv, center);
    t = dist * 2.0; // 0〜1範囲に正規化
  }

  // カラーストップの配列
  float4 stops = float4(stop1, stop2, stop3, stop4);

  // どのセグメントにいるかを判定
  float3 resultColor;

  if (t <= stops.x) {
    // Before first stop
    resultColor = float3(color1.rgb);

  } else if (t <= stops.y) {
    // Between stop1 and stop2
    float localT = getLocalT(t, stops.x, stops.y);
    float3 c1 = float3(color1.rgb);
    float3 c2 = float3(color2.rgb);

    if (colorSpaceInt == 0) {
      resultColor = interpolateSRGB(c1, c2, localT);
    } else if (colorSpaceInt == 1) {
      resultColor = interpolateOKLAB(c1, c2, localT);
    } else {
      resultColor = interpolateOKLCH(c1, c2, localT);
    }

  } else if (t <= stops.z) {
    // Between stop2 and stop3
    float localT = getLocalT(t, stops.y, stops.z);
    float3 c2 = float3(color2.rgb);
    float3 c3 = float3(color3.rgb);

    if (colorSpaceInt == 0) {
      resultColor = interpolateSRGB(c2, c3, localT);
    } else if (colorSpaceInt == 1) {
      resultColor = interpolateOKLAB(c2, c3, localT);
    } else {
      resultColor = interpolateOKLCH(c2, c3, localT);
    }

  } else if (t <= stops.w) {
    // Between stop3 and stop4
    float localT = getLocalT(t, stops.z, stops.w);
    float3 c3 = float3(color3.rgb);
    float3 c4 = float3(color4.rgb);

    if (colorSpaceInt == 0) {
      resultColor = interpolateSRGB(c3, c4, localT);
    } else if (colorSpaceInt == 1) {
      resultColor = interpolateOKLAB(c3, c4, localT);
    } else {
      resultColor = interpolateOKLCH(c3, c4, localT);
    }

  } else {
    // After last stop
    resultColor = float3(color4.rgb);
  }

  // HDR輝度を適用
  half3 result = half3(resultColor) * peakBrightness;

  // ソフトクリッピング: headroomに近づくとなめらかに圧縮
  float maxComponent = max(max(result.r, result.g), result.b);
  if (maxComponent > headroom * 0.8) {
    float compressionStart = headroom * 0.8;
    float compressionRange = headroom - compressionStart;

    result.r = result.r <= compressionStart ? result.r : compressionStart + compressionRange * (result.r - compressionStart) / (result.r - compressionStart + compressionRange);
    result.g = result.g <= compressionStart ? result.g : compressionStart + compressionRange * (result.g - compressionStart) / (result.g - compressionStart + compressionRange);
    result.b = result.b <= compressionStart ? result.b : compressionStart + compressionRange * (result.b - compressionStart) / (result.b - compressionStart + compressionRange);
  }

  return half4(result, 1.0);
}
