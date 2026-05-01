#include <metal_stdlib>
#include "../Shaders/ColorSpace.h"
using namespace metal;

// 疑似乱数生成（hash関数）
float hash(float n) {
  return fract(sin(n) * 43758.5453123);
}

// 1Dノイズ（補間付き）
float noise1D(float x) {
  float i = floor(x);
  float f = fract(x);
  // スムーズ補間
  float u = f * f * (3.0 - 2.0 * f);
  return mix(hash(i), hash(i + 1.0), u);
}

// 1/fノイズ（fBm: Fractional Brownian Motion）
// 複数のオクターブのノイズを1/fの重みで合成
float pinkNoise(float time, int octaves) {
  float value = 0.0;
  float amplitude = 1.0;
  float frequency = 1.0;
  float maxValue = 0.0;

  for (int i = 0; i < octaves; i++) {
    value += amplitude * noise1D(time * frequency);
    maxValue += amplitude;
    amplitude *= 0.5;   // 振幅を半減（1/f特性）
    frequency *= 2.0;   // 周波数を倍増
  }

  return value / maxValue;  // 0〜1に正規化
}

// コントラストカーブ：ノイズ値を極端な方向（0と1）に押しやる
// exponent < 1.0 で中央から離れやすくなる
float applyContrast(float value, float exponent) {
  float centered = (value - 0.5) * 2.0;  // -1〜1に変換
  float sign = centered >= 0.0 ? 1.0 : -1.0;
  float curved = sign * pow(abs(centered), exponent);
  return curved * 0.5 + 0.5;  // 0〜1に戻す
}

// SwiftUI用のカラーエフェクトシェーダー（EDR対応）
// allowedDynamicRange(.high)と組み合わせることで、
// 1.0を超える値がHDRディスプレイで実際に明るく表示される
[[ stitchable ]] half4 ambientFog(
  float2 position,
  half4 currentColor,
  float2 size,
  float time,
  float gridCols,       // グリッドの列数
  float gridRows,       // グリッドの行数
  float speed,          // ノイズの速度（0.1〜2.0）
  float dimFactor,      // 最も暗い時の輝度（0.0〜1.0、1.0で変化なし）
  float peakBrightness, // ピーク輝度（1.0〜2.0、HDRの眩しさを強調）
  float headroom,       // HDR headroom（最大輝度制限、1.0〜8.0）
  half4 baseColor       // ベースカラー（最も明るい時の色、HDR値可）
) {
  // ピクセル位置からグリッドセルを計算
  float cellWidth = size.x / gridCols;
  float cellHeight = size.y / gridRows;
  int col = int(position.x / cellWidth);
  int row = int(position.y / cellHeight);

  // セルインデックスをシードとして使用
  float seed = float(row * int(gridCols) + col);

  // 1/fノイズを計算（6オクターブ）
  float noise = pinkNoise(time * speed + seed * 100.0, 6);

  // コントラストを適用して暗い方向にも振れやすくする
  noise = applyContrast(noise, 0.6);

  // 輝度: dimFactor（最暗）〜 peakBrightness（最明＝HDRピーク）
  // peakBrightness > 1.0 の場合、baseColor以上の明るさになりHDRが活きる
  float brightness = dimFactor + noise * (peakBrightness - dimFactor);

  // baseColorに輝度を適用
  // brightness > 1.0 の場合、HDRカラーがさらに増幅される
  half3 result = baseColor.rgb * brightness;

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
