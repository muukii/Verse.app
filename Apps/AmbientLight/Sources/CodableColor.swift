import SwiftUI

/// SwiftUI.ColorのCodable対応ラッパー
struct CodableColor: Codable, Equatable {
  var red: Double
  var green: Double
  var blue: Double
  var opacity: Double

  init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }

  init(_ color: Color) {
    let resolved = color.resolve(in: EnvironmentValues())
    self.red = Double(resolved.red)
    self.green = Double(resolved.green)
    self.blue = Double(resolved.blue)
    self.opacity = Double(resolved.opacity)
  }

  /// HSB (Hue, Saturation, Brightness) 形式で色を初期化
  /// - Parameters:
  ///   - hue: 色相 (0.0-1.0)。度数で指定する場合は÷360
  ///   - saturation: 彩度 (0.0-1.0)
  ///   - brightness: 明度 (0.0-1.0)
  ///   - opacity: 不透明度 (0.0-1.0)、デフォルトは1.0
  init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1.0) {
    let color = Color(hue: hue, saturation: saturation, brightness: brightness, opacity: opacity)
    self.init(color)
  }

  /// Hex文字列から色を初期化
  /// - Parameters:
  ///   - hex: Hex文字列 ("#RRGGBB", "#RRGGBBAA", "RRGGBB"形式)
  /// - Returns: パースに成功した場合はCodableColor、失敗した場合はnil
  init?(hex: String) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0

    guard Scanner(string: hex).scanHexInt64(&int) else {
      return nil
    }

    let r, g, b, a: UInt64
    switch hex.count {
    case 6: // RGB (without alpha)
      (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
    case 8: // RGBA (with alpha)
      (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default:
      return nil
    }

    self.init(
      red: Double(r) / 255.0,
      green: Double(g) / 255.0,
      blue: Double(b) / 255.0,
      opacity: Double(a) / 255.0
    )
  }

  /// Hex整数値から色を初期化
  /// - Parameters:
  ///   - hex: Hex整数値 (例: 0xFA6D24)
  ///   - opacity: 不透明度 (0.0-1.0)、デフォルトは1.0
  init(hex: Int, opacity: Double = 1.0) {
    let r = (hex >> 16) & 0xFF
    let g = (hex >> 8) & 0xFF
    let b = hex & 0xFF

    self.init(
      red: Double(r) / 255.0,
      green: Double(g) / 255.0,
      blue: Double(b) / 255.0,
      opacity: opacity
    )
  }

  var color: Color {
    Color(red: red, green: green, blue: blue, opacity: opacity)
  }
}
