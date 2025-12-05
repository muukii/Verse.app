//
//  YouTubeSubtitleApp.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftData
import SwiftUI

@main
struct YouTubeSubtitleApp: App {

  let modelContainer: ModelContainer
  @State private var downloadManager = DownloadManager()

  init() {
    // Configure audio session for video playback (allows audio in silent mode)
    _ = AudioSessionManager.shared

    // Configure ModelContainer with all schemas
    let schema = Schema([
      VideoHistoryItem.self,
      DownloadRecord.self,
    ])

    do {
      modelContainer = try ModelContainer(for: schema)
    } catch {
      fatalError("Failed to create ModelContainer: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          // Configure and restore pending downloads on app launch
          downloadManager.configure(modelContainer: modelContainer)
          await downloadManager.restorePendingDownloads()
        }
    }
    .defaultSize(width: 800, height: 600)
    .modelContainer(modelContainer)
    .environment(downloadManager)
  }
}
