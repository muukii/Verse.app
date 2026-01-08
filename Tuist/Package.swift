// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
  productTypes: [
:
  ]
)
#endif

let package = Package(
  name: "Verse",
  dependencies: [
    // YouTube related
    .package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.4.0"),
    .package(url: "https://github.com/spaceman1412/swift-youtube-transcript", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),

    // UI components
    .package(url: "https://github.com/FluidGroup/swiftui-object-edge", from: "1.0.0"),
    .package(url: "https://github.com/FluidGroup/swiftui-ring-slider", from: "0.2.0"),
    .package(url: "https://github.com/FluidGroup/swiftui-async-multiplex-image", from: "1.0.0"),

    // State management and utilities
    .package(url: "https://github.com/VergeGroup/swift-typed-identifier", from: "2.0.4"),
    .package(url: "https://github.com/VergeGroup/swift-state-graph", from: "0.16.0"),
  ]
)
