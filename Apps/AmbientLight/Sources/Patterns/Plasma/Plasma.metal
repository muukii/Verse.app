#include <metal_stdlib>
#include "../Shaders/ColorSpace.h"
using namespace metal;

// 複数のサイン波を組み合わせてプラズマパターンを生成
float plasmaPattern(float2 position, float time, float frequency, float complexity) {
  float2 p = position * frequency;

  // 複数のサイン波を重ね合わせる
  float v = 0.0;

  // 水平波
  v += sin(p.x + time);

  // 垂直波
  v += sin(p.y + time * 1.3);

  // 斜め波1
  v += sin((p.x + p.y) * 0.5 + time * 0.7);

  // 斜め波2
  v += sin((p.x - p.y) * 0.5 + time * 0.9);

  // 回転する円形波
  float dist = length(p - float2(sin(time * 0.5), cos(time * 0.5)) * 2.0);
  v += sin(dist * complexity + time * 1.5);

  // 反対回転の円形波
  float dist2 = length(p - float2(cos(time * 0.3), sin(time * 0.3)) * 2.0);
  v += sin(dist2 * complexity * 0.7 - time * 1.2);

  // 正規化（-6〜6 → 0〜1）
  return (v + 6.0) / 12.0;
}

// SwiftUI用のプラズマシェーダー（HDR対応）
[[ stitchable ]] half4 plasma(
  float2 position,
  half4 currentColor,
  float2 size,
  float time,
  float speed,           // 動きの速度（0.1〜3.0）
  float frequency,       // パターンの細かさ（0.5〜5.0）
  float complexity,      // 複雑さ（1.0〜5.0）
  float colorSpeed,      // 色の変化速度（0.1〜2.0）
  float saturation,      // 彩度（0.0〜1.0）
  float peakBrightness,  // ピーク輝度（1.0〜8.0）
  float headroom,        // HDR headroom（最大輝度制限、1.0〜8.0）
  half4 baseColor        // ベースカラー（HDR、色相のオフセットとして使用）
) {
  // 正規化座標
  float2 uv = position / size;

  // アスペクト比を考慮
  float aspect = size.x / size.y;
  float2 p = float2(uv.x * aspect, uv.y);

  // プラズマパターンを生成
  float plasma = plasmaPattern(p, time * speed, frequency, complexity);

  // 色相を時間で変化させる
  float hue = fract(plasma + time * colorSpeed * 0.1 + float(baseColor.r) * 0.3);

  // HSVからRGBへ変換
  float3 color = hsv2rgb(float3(hue, saturation, 1.0));

  // プラズマの明暗パターンで輝度を変調
  float brightness = pow(plasma, 1.5) * peakBrightness;

  // HDRカラーを適用
  half3 result = half3(color) * brightness * baseColor.rgb;

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
