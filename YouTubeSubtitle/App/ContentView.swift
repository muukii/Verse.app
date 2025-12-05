//
//  ContentView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(DownloadManager.self) private var downloadManager
  @State private var historyService: VideoHistoryService?

  var body: some View {
    Group {
      if let service = historyService {
        HomeView()
          .environment(service)
      } else {
        ProgressView()
      }
    }
    .onAppear {
      if historyService == nil {
        historyService = VideoHistoryService(
          modelContext: modelContext,
          downloadManager: downloadManager
        )
      }
    }
  }
}

#Preview {
  ContentView()
}
