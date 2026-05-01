#include <metal_stdlib>
#include "../Shaders/ColorSpace.h"
using namespace metal;

// 疑似乱数生成
float hash(float2 p) {
  float h = dot(p, float2(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

// 2Dノイズ（補間付き）
float noise2D(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);

  // スムーズ補間
  float2 u = f * f * (3.0 - 2.0 * f);

  // 4つのコーナーをミックス
  float a = hash(i);
  float b = hash(i + float2(1.0, 0.0));
  float c = hash(i + float2(0.0, 1.0));
  float d = hash(i + float2(1.0, 1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// フラクタルブラウニアンモーション（fBm）
float fbm(float2 p, int octaves) {
  float value = 0.0;
  float amplitude = 0.5;
  float frequency = 1.0;

  for (int i = 0; i < octaves; i++) {
    value += amplitude * noise2D(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }

  return value;
}

// オーロラのようなカーテン状の波を生成
float auroraWave(float2 position, float time, float speed, float waveHeight) {
  // 複数の波を重ね合わせる
  float wave1 = sin(position.x * 0.5 + time * speed) * waveHeight;
  float wave2 = sin(position.x * 0.8 + time * speed * 1.3) * waveHeight * 0.5;
  float wave3 = sin(position.x * 1.2 + time * speed * 0.7) * waveHeight * 0.3;

  return wave1 + wave2 + wave3;
}

// SwiftUI用のオーロラシェーダー（HDR対応）
[[ stitchable ]] half4 aurora(
  float2 position,
  half4 currentColor,
  float2 size,
  float time,
  float speed,           // 動きの速度（0.1〜2.0）
  float waveHeight,      // 波の高さ（0.1〜1.0）
  float flowDirection,   // 流れる方向（0.0〜1.0、0=上、1=下）
  float peakBrightness,  // ピーク輝度（1.0〜8.0）
  float headroom,        // HDR headroom（最大輝度制限、1.0〜8.0）
  half4 color1,          // グラデーションカラー1（HDR）
  half4 color2,          // グラデーションカラー2（HDR）
  half4 color3           // グラデーションカラー3（HDR）
) {
  // 正規化座標（0〜1）
  float2 uv = position / size;

  // 縦方向を基準に
  float2 p = float2(uv.x * 3.0, uv.y * 2.0);

  // 時間に応じた流れ（上または下）
  float flow = mix(-time * speed, time * speed, flowDirection);
  p.y += flow;

  // オーロラのカーテン状の波
  float wave = auroraWave(p, time * speed, speed, waveHeight);

  // ノイズでオーロラの揺らぎを追加
  float noise = fbm(p + float2(0.0, time * speed * 0.5), 4);

  // Y座標を波で歪ませる
  float distortedY = uv.y + wave * 0.2 + noise * 0.1;

  // 縦方向のグラデーション（3色）
  half3 gradient;
  if (distortedY < 0.4) {
    // color1 → color2
    float t = distortedY / 0.4;
    gradient = mix(color1.rgb, color2.rgb, t);
  } else {
    // color2 → color3
    float t = (distortedY - 0.4) / 0.6;
    gradient = mix(color2.rgb, color3.rgb, t);
  }

  // 不透明度マスク：中央が明るく、端が暗い
  float centerMask = 1.0 - abs(uv.x - 0.5) * 2.0;
  centerMask = pow(centerMask, 2.0);

  // 縦方向の明るさの変動
  float verticalMask = sin(distortedY * 3.14159 * 2.0 + noise * 6.28318) * 0.5 + 0.5;

  // 最終的な輝度
  float brightness = centerMask * verticalMask * noise * peakBrightness;

  // カラーに輝度を適用
  half3 result = gradient * brightness;

  // ソフトクリッピング: headroomに近づくとなめらかに圧縮
  // Reinhard tone mapping の変形版
  // headroom付近で滑らかに収束し、ハードクリッピングを避ける
  float maxComponent = max(max(result.r, result.g), result.b);
  if (maxComponent > headroom * 0.8) {
    // headroomの80%を超えたらソフトクリッピング開始
    float compressionStart = headroom * 0.8;
    float compressionRange = headroom - compressionStart;

    // 各チャンネルに対してソフトクリッピングを適用
    result.r = result.r <= compressionStart ? result.r : compressionStart + compressionRange * (result.r - compressionStart) / (result.r - compressionStart + compressionRange);
    result.g = result.g <= compressionStart ? result.g : compressionStart + compressionRange * (result.g - compressionStart) / (result.g - compressionStart + compressionRange);
    result.b = result.b <= compressionStart ? result.b : compressionStart + compressionRange * (result.b - compressionStart) / (result.b - compressionStart + compressionRange);
  }

  return half4(result, 1.0);
}
