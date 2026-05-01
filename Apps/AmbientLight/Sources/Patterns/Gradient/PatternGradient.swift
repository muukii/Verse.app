import SwiftUI

struct PatternGradient: View {

  @State private var parameters = ShaderParameters()

  var body: some View {

    Display(
      matrixX: MatrixBinding($parameters.angle, range: 0...360),
      matrixY: MatrixBinding($parameters.animate, range: 0...2.0)
    ) {
      _BodyView(parameters: parameters)
    } settingsContent: {

      // Color Space Selection
      Picker("Color Space", selection: $parameters.colorSpace) {
        Text("sRGB").tag(ColorSpace.srgb)
        Text("OKLAB").tag(ColorSpace.oklab)
        Text("OKLCH").tag(ColorSpace.oklch)
      }
      .pickerStyle(.segmented)

      Divider()

      // Gradient Type
      Picker("Type", selection: $parameters.gradientType) {
        Text("Linear").tag(GradientType.linear)
        Text("Radial").tag(GradientType.radial)
      }
      .pickerStyle(.segmented)

      Divider()

      // Angle (for linear gradients)
      if parameters.gradientType == .linear {
        VStack(alignment: .leading) {
          Text("Angle: \(parameters.angle, specifier: "%.0f")°")
          Slider(value: $parameters.angle, in: 0...360)
        }
      }

      // Animation
      VStack(alignment: .leading) {
        Text("Animation: \(parameters.animate, specifier: "%.2f")")
        Slider(value: $parameters.animate, in: 0...2.0)
      }

      Divider()

      // Color Stops
      Group {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Color 1")
            Spacer()
            Text("\(Int(parameters.stop1 * 100))%")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
          ColorPicker("", selection: $parameters.color1)
            .labelsHidden()
          Slider(value: $parameters.stop1, in: 0...1)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Color 2")
            Spacer()
            Text("\(Int(parameters.stop2 * 100))%")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
          ColorPicker("", selection: $parameters.color2)
            .labelsHidden()
          Slider(value: $parameters.stop2, in: 0...1)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Color 3")
            Spacer()
            Text("\(Int(parameters.stop3 * 100))%")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
          ColorPicker("", selection: $parameters.color3)
            .labelsHidden()
          Slider(value: $parameters.stop3, in: 0...1)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Color 4")
            Spacer()
            Text("\(Int(parameters.stop4 * 100))%")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
          ColorPicker("", selection: $parameters.color4)
            .labelsHidden()
          Slider(value: $parameters.stop4, in: 0...1)
        }
      }

      Divider()

      // HDR Settings
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

private enum ColorSpace: Int, Codable {
  case srgb = 0
  case oklab = 1
  case oklch = 2
}

private enum GradientType: Int, Codable {
  case linear = 0
  case radial = 1
}

private struct ShaderParameters: Codable {
  var colorSpace: ColorSpace = .srgb
  var gradientType: GradientType = .linear
  var angle: Float = 0.0
  var animate: Float = 0.0

  // Color stops
  var _color1: CodableColor = .init(red: 1.0, green: 0.0, blue: 0.0)  // Red
  var _color2: CodableColor = .init(red: 1.0, green: 1.0, blue: 0.0)  // Yellow
  var _color3: CodableColor = .init(red: 0.0, green: 1.0, blue: 0.0)  // Green
  var _color4: CodableColor = .init(red: 0.0, green: 0.0, blue: 1.0)  // Blue

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

  var color4: Color {
    get { _color4.color }
    set { _color4 = CodableColor(newValue) }
  }

  // Stop positions (0.0 to 1.0)
  var stop1: Float = 0.0
  var stop2: Float = 0.33
  var stop3: Float = 0.66
  var stop4: Float = 1.0

  // HDR settings
  var headroom: Float = 4.0
  var peakBrightness: Float = 1.0

  // HDR colors (with headroom applied)
  var hdrColor1: Color {
    let resolved = color1.resolve(in: EnvironmentValues())
    return Color(Color.ResolvedHDR(resolved, headroom: headroom))
  }

  var hdrColor2: Color {
    let resolved = color2.resolve(in: EnvironmentValues())
    return Color(Color.ResolvedHDR(resolved, headroom: headroom))
  }

  var hdrColor3: Color {
    let resolved = color3.resolve(in: EnvironmentValues())
    return Color(Color.ResolvedHDR(resolved, headroom: headroom))
  }

  var hdrColor4: Color {
    let resolved = color4.resolve(in: EnvironmentValues())
    return Color(Color.ResolvedHDR(resolved, headroom: headroom))
  }

  enum CodingKeys: String, CodingKey {
    case colorSpace, gradientType, angle, animate
    case _color1 = "color1"
    case _color2 = "color2"
    case _color3 = "color3"
    case _color4 = "color4"
    case stop1, stop2, stop3, stop4
    case headroom, peakBrightness
  }
}

/// Metal Shaderを使ったグラデーションエフェクト
private struct _BodyView: View {
  let parameters: ShaderParameters

  var body: some View {
    PhaseTimelineView(speed: parameters.animate) { phase, size in
      Rectangle()
        .fill(.black)
        .colorEffect(
          ShaderLibrary.gradient(
            .float2(size),
            .float(phase),
            .float(parameters.angle),
            .float(Float(parameters.colorSpace.rawValue)),
            .float(Float(parameters.gradientType.rawValue)),
            .color(parameters.hdrColor1),
            .color(parameters.hdrColor2),
            .color(parameters.hdrColor3),
            .color(parameters.hdrColor4),
            .float(parameters.stop1),
            .float(parameters.stop2),
            .float(parameters.stop3),
            .float(parameters.stop4),
            .float(parameters.peakBrightness),
            .float(parameters.headroom),
            .float(1.0)  // animate speed is already integrated into phase
          )
        )
    }
  }
}

// MARK: - Preview

#Preview("Gradient") {
  _BodyView(parameters: ShaderParameters())
}
