import SwiftUI

struct PatternVapor: View {

  @State private var parameters = ShaderParameters()

  var body: some View {

    Display(
      matrixX: MatrixBinding($parameters.speed, range: 0.1...3.0),
      matrixY: MatrixBinding($parameters.density, range: 0.3...3.0)
    ) {
      _BodyView(parameters: parameters)
    } settingsContent: {

      VStack(alignment: .leading) {
        Text("Speed: \(parameters.speed, specifier: "%.2f")")
        Slider(value: $parameters.speed, in: 0.1...3.0)
      }

      VStack(alignment: .leading) {
        Text("Density: \(parameters.density, specifier: "%.2f")")
        Slider(value: $parameters.density, in: 0.3...3.0)
      }

      VStack(alignment: .leading) {
        Text("Drift: \(parameters.turbulence, specifier: "%.2f")")
        Slider(value: $parameters.turbulence, in: 0.0...2.0)
      }

      VStack(alignment: .leading) {
        Text("Scale: \(parameters.scale, specifier: "%.1f")")
        Slider(value: $parameters.scale, in: 0.5...5.0)
      }

      VStack(alignment: .leading) {
        Text("Glow: \(parameters.swirlAmount, specifier: "%.2f")")
        Slider(value: $parameters.swirlAmount, in: 0.0...2.0)
      }

      ColorPicker("Color 1", selection: $parameters.color1)
      ColorPicker("Color 2", selection: $parameters.color2)
      ColorPicker("Highlight", selection: $parameters.color3)

      VStack(alignment: .leading) {
        Text("HDR Headroom: \(parameters.headroom, specifier: "%.1f")x")
        Slider(value: $parameters.headroom, in: 1.0...8.0)
      }

      VStack(alignment: .leading) {
        Text("Peak Brightness: \(parameters.peakBrightness, specifier: "%.1f")x")
        Slider(value: $parameters.peakBrightness, in: 1.0...8.0)
      }
    }

  }

}

private struct ShaderParameters: Codable {
  var speed: Float = 0.4
  var density: Float = 1.2
  var turbulence: Float = 0.8
  var scale: Float = 2.0
  var swirlAmount: Float = 0.8  // グローの広がり

  var _color1: CodableColor = .init(hex: 0x1A0A2E)  // 深い紫
  var _color2: CodableColor = .init(hex: 0x4A90D9)  // ブルー
  var _color3: CodableColor = .init(hex: 0xE8D5B7)  // 暖かいホワイト

  var color1: Color {
    get { _color1.color }
    set { _color1 = CodableColor(newValue) }
  }
  var color2: Color {
    get { _color2.color }
    set { _color2 = CodableColor(newValue) }
  }
  var color3: Color {
    get { _color3.color }
    set { _color3 = CodableColor(newValue) }
  }

  var headroom: Float = 6.0
  var peakBrightness: Float = 3.0

  func hdrColor(_ color: Color) -> Color {
    let resolved = color.resolve(in: EnvironmentValues())
    return Color(Color.ResolvedHDR(resolved, headroom: headroom))
  }

  enum CodingKeys: String, CodingKey {
    case speed, density, turbulence, scale, swirlAmount
    case _color1 = "color1"
    case _color2 = "color2"
    case _color3 = "color3"
    case headroom, peakBrightness
  }
}

/// Metal Shaderを使ったVapor（浮遊する光の粒子）エフェクト
private struct _BodyView: View {
  let parameters: ShaderParameters

  var body: some View {
    PhaseTimelineView(speed: parameters.speed) { phase, size in
      Rectangle()
        .fill(.black)
        .colorEffect(
          ShaderLibrary.vapor(
            .float2(size),
            .float(phase),
            .float(1.0),  // speed is already integrated into phase
            .float(parameters.density),
            .float(parameters.turbulence),
            .float(parameters.scale),
            .float(parameters.swirlAmount),
            .float(parameters.peakBrightness),
            .float(parameters.headroom),
            .color(parameters.hdrColor(parameters.color1)),
            .color(parameters.hdrColor(parameters.color2)),
            .color(parameters.hdrColor(parameters.color3))
          )
        )
    }
  }
}

// MARK: - Preview

#Preview("Vapor") {
  _BodyView(parameters: ShaderParameters())
}
