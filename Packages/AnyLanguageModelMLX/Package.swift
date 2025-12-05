// swift-tools-version: 6.1
// Wrapper package to enable MLX trait for AnyLanguageModel in Xcode

import PackageDescription

let package = Package(
  name: "AnyLanguageModelMLX",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: [
    .library(
      name: "AnyLanguageModelMLX",
      targets: ["AnyLanguageModelMLX"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/mattt/AnyLanguageModel.git",
      branch: "main",
      traits: ["MLX"]  // Enable MLX trait
    )
  ],
  targets: [
    .target(
      name: "AnyLanguageModelMLX",
      dependencies: [
        .product(name: "AnyLanguageModel", package: "AnyLanguageModel")
      ]
    )
  ]
)
