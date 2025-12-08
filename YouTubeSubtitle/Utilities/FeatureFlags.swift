//
//  FeatureFlags.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/08.
//

import Foundation

/// Feature flags for controlling app functionality.
/// Use these flags to enable/disable features for different builds or configurations.
@MainActor
final class FeatureFlags {
  /// Shared singleton instance
  static let shared = FeatureFlags()

  private init() {}

  // MARK: - Feature Flags

  /// Controls whether video download functionality is visible in the UI.
  ///
  /// When disabled:
  /// - Download button is hidden in PlayerView
  /// - Download status indicators are hidden in HomeView
  /// - DownloadView sheet is not accessible
  ///
  /// Note: Backend download functionality (DownloadManager) remains available
  /// for programmatic use (e.g., for transcription purposes).
  ///
  /// Default: false (hidden for App Store submission)
  /// Set to true for personal builds or TestFlight builds where download is needed.
  var isDownloadFeatureEnabled: Bool {
    #if DEBUG
    // Enable in debug builds for development
    return true
    #else
    // Disable in release builds for App Store submission
    // Change this to true for personal release builds
    return false
    #endif
  }

  // MARK: - Future Flags

  // Add additional feature flags here as needed:
  // var isNewFeatureEnabled: Bool { true }
}
