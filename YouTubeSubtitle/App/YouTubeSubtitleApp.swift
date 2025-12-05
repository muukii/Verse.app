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

  init() {
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

    // Configure DownloadManager
    DownloadManager.shared.configure(modelContainer: modelContainer)
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          // Restore pending downloads on app launch
          await DownloadManager.shared.restorePendingDownloads()
        }
    }
    .defaultSize(width: 800, height: 600)
    .modelContainer(modelContainer)
  }
}
