//
//  YouTubeSubtitleApp.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import SwiftData

@main
struct YouTubeSubtitleApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .defaultSize(width: 800, height: 600)
    .modelContainer(for: VideoHistoryItem.self)
  }
}
