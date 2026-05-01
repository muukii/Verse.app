#include <metal_stdlib>
using namespace metal;

// ========================================
// Vapor: 浮遊する光の粒子
//
// 空間に漂う無数の光の塵。
// ボロノイセルの中心点をパーティクルとして使い、
// 各粒子が独立して漂い、明滅する。
// 全体としてアンビエントな光のテクスチャになる。
// ========================================

// --- ハッシュ関数 ---

float2 vaporHash2(float2 p) {
  p = float2(dot(p, float2(127.1, 311.7)),
             dot(p, float2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453123);
}

float vaporHash1(float n) {
  return fract(sin(n * 127.1) * 43758.5453123);
}

// --- シンプルノイズ（背景のフロー用）---

float vaporNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  float2 u = f * f * (3.0 - 2.0 * f);

  float a = dot(vaporHash2(i), float2(1.0));
  float b = dot(vaporHash2(i + float2(1.0, 0.0)), float2(1.0));
  float c = dot(vaporHash2(i + float2(0.0, 1.0)), float2(1.0));
  float d = dot(vaporHash2(i + float2(1.0, 1.0)), float2(1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// --- メインシェーダー ---

[[ stitchable ]] half4 vapor(
  float2 position,
  half4 currentColor,
  float2 size,
  float time,
  float speed,           // 動きの速度
  float density,         // 粒子の密度（グリッドの細かさ）
  float turbulence,      // 粒子の動きの大きさ
  float scale,           // 全体のスケール
  float swirlAmount,     // グローの広がり
  float peakBrightness,  // ピーク輝度
  float headroom,        // HDR headroom
  half4 color1,          // カラー1
  half4 color2,          // カラー2
  half4 color3           // カラー3（ハイライト）
) {
  float2 uv = position / size;
  float aspect = size.x / size.y;
  float t = time * speed;

  float2 p = float2(uv.x * aspect, uv.y) * scale * density;

  // ============================
  // ボロノイベースのパーティクルシステム
  // ============================
  // ボロノイの各セル中心点 = 1つの粒子
  // 粒子が時間とともに動き、明滅する

  half3 totalColor = half3(0.0);

  // 3レイヤー（異なる密度・速度で奥行き感を出す）
  for (int layer = 0; layer < 3; layer++) {
    float fl = float(layer);
    float layerScale = 1.0 + fl * 0.8;           // 奥: 粗い、手前: 細かい
    float layerSpeed = (0.4 + fl * 0.3) * t;     // 奥: 遅い、手前: 速い
    float layerBright = 0.25 + fl * 0.15;         // 奥: 暗い、手前: 明るい

    float2 lp = p * layerScale + float2(fl * 5.3, fl * 3.7);

    // 全体的なゆるやかなフロー（風に流される動き）
    float2 flow = float2(
      sin(layerSpeed * 0.13 + fl * 1.1) * 0.5 + cos(layerSpeed * 0.07) * 0.3,
      cos(layerSpeed * 0.11 + fl * 0.7) * 0.4 + sin(layerSpeed * 0.09) * 0.2
    ) * turbulence;

    lp += flow;

    // ボロノイ
    float2 cellId = floor(lp);
    float2 cellUv = fract(lp);

    float minDist = 10.0;
    float secondDist = 10.0;
    float2 closestPoint = float2(0.0);
    float closestHash = 0.0;

    // 3x3近傍を探索
    for (int y = -1; y <= 1; y++) {
      for (int x = -1; x <= 1; x++) {
        float2 neighbor = float2(float(x), float(y));
        float2 cell = cellId + neighbor;

        // 各粒子の位置（ゆっくり漂う）
        float2 basePos = vaporHash2(cell);
        float cellSeed = dot(cell, float2(127.1, 311.7));

        // 粒子ごとの個別の動き
        float2 drift = float2(
          sin(layerSpeed * (0.2 + vaporHash1(cellSeed + 1.0) * 0.15) + cellSeed) * 0.35,
          cos(layerSpeed * (0.15 + vaporHash1(cellSeed + 2.0) * 0.15) + cellSeed * 1.3) * 0.35
        ) * turbulence;

        float2 point = neighbor + basePos + drift;
        float2 diff = point - cellUv;
        float dist = length(diff);

        if (dist < minDist) {
          secondDist = minDist;
          minDist = dist;
          closestPoint = cell + basePos;
          closestHash = vaporHash1(cellSeed + 3.0);
        } else if (dist < secondDist) {
          secondDist = dist;
        }
      }
    }

    // ============================
    // 粒子の描画
    // ============================

    // グロー半径（swirlAmountで制御）
    float glowRadius = 0.08 + swirlAmount * 0.12;

    // ソフトなガウシアングロー
    float glow = exp(-minDist * minDist / (glowRadius * glowRadius));

    // コア（中心の明るい点）
    float coreRadius = glowRadius * 0.15;
    float core = exp(-minDist * minDist / (coreRadius * coreRadius));

    // 明滅（各粒子が独立してゆっくり瞬く）
    float pulseSpeed = 0.3 + closestHash * 0.5;
    float pulsePhase = closestHash * 6.28318;
    float pulse = 0.5 + 0.5 * sin(t * pulseSpeed + pulsePhase);
    // パルスをソフトに: 完全に消えず、0.3〜1.0の範囲
    pulse = 0.3 + pulse * 0.7;

    // 粒子の明るさ
    float particleBright = (glow * 0.6 + core * 0.4) * pulse * layerBright;

    // 粒子ごとの色（3色からハッシュで選ぶ）
    half3 particleColor;
    float colorSelect = vaporHash1(closestHash * 137.0 + fl * 17.0);
    if (colorSelect < 0.33) {
      particleColor = mix(color1.rgb, color2.rgb, colorSelect * 3.0);
    } else if (colorSelect < 0.66) {
      particleColor = mix(color2.rgb, color3.rgb, (colorSelect - 0.33) * 3.0);
    } else {
      particleColor = mix(color3.rgb, color1.rgb, (colorSelect - 0.66) * 3.0);
    }

    // コア部分はcolor3寄りにして明るいハイライト感
    half3 coreColor = mix(particleColor, color3.rgb, 0.5);
    half3 finalColor = mix(particleColor, coreColor, core / max(glow * 0.6 + core * 0.4, 0.001));

    totalColor += finalColor * particleBright;
  }

  // ============================
  // 背景のうっすらとしたノイズ（完全な黒にしない）
  // ============================

  float bgNoise = vaporNoise(p * 0.3 + float2(t * 0.05, t * 0.03));
  half3 bgColor = mix(color1.rgb, color2.rgb, bgNoise) * 0.02;

  half3 result = (totalColor + bgColor) * peakBrightness;

  // ソフトクリッピング
  float maxComponent = max(max(result.r, result.g), result.b);
  if (maxComponent > headroom * 0.8) {
    float compressionStart = headroom * 0.8;
    float compressionRange = headroom - compressionStart;

    result.r = result.r <= compressionStart ? result.r :
      compressionStart + compressionRange * (result.r - compressionStart) /
      (result.r - compressionStart + compressionRange);
    result.g = result.g <= compressionStart ? result.g :
      compressionStart + compressionRange * (result.g - compressionStart) /
      (result.g - compressionStart + compressionRange);
    result.b = result.b <= compressionStart ? result.b :
      compressionStart + compressionRange * (result.b - compressionStart) /
      (result.b - compressionStart + compressionRange);
  }

  return half4(result, 1.0);
}
