//
//  HomeView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import SwiftData
import AppIntents

struct HomeView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(VideoItemService.self) private var historyService
  @Environment(VocabularyService.self) private var vocabularyService
  @Environment(DownloadManager.self) private var downloadManager
  @Query(sort: \VideoItem.timestamp, order: .reverse) private var history: [VideoItem]

  @State private var selectedVideoItem: VideoItem?
  @State private var showWebView: Bool = false
  @State private var showSettings: Bool = false
  @State private var showURLInput: Bool = false
  @State private var videoToAddToPlaylist: VideoItem?
  @ObservedObject private var deepLinkManager = DeepLinkManager.shared

  @Namespace private var heroNamespace

  var body: some View {
    NavigationStack {
      Group {
        // History List
        if history.isEmpty {
          ContentUnavailableView {
            Label("Verse", systemImage: "captions.bubble.fill")
          } description: {
            Text("Watch YouTube videos with synced subtitles.\nPaste a URL or browse YouTube to get started.")
          } actions: {
            Button {
              loadDemoVideo()
            } label: {
              Label("Try Demo Video", systemImage: "play.circle")
            }
            .buttonStyle(.bordered)
          }
        } else {
          List {
            ForEach(history) { item in
              Button {
                selectedVideoItem = item
              } label: {
                VideoItemCell(
                  video: item,
                  namespace: heroNamespace,
                  downloadManager: downloadManager,
                  showTimestamp: true
                )
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button {
                  videoToAddToPlaylist = item
                } label: {
                  Label("Add to Playlist", systemImage: "text.badge.plus")
                }
              }
            }
            .onDelete { indexSet in
              Task {
                for index in indexSet {
                  let item = history[index]
                  try? await historyService.deleteHistoryItem(item)
                }
              }
            }
          }
          .listStyle(.inset)
        }
      }
      .navigationTitle("")
      .toolbar {
        // Top toolbar - Settings
        ToolbarItem(placement: .primaryAction) {
          Button {
            showSettings = true
          } label: {
            Label("Settings", systemImage: "gear")
          }
        }
        if !history.isEmpty {
          ToolbarItem(placement: .secondaryAction) {
            Button(role: .destructive) {
              Task {
                try? await historyService.clearAllHistory()
              }
            } label: {
              Label("Clear History", systemImage: "trash")
            }
          }
        }

        // Bottom toolbar - Main actions
        ToolbarItemGroup(placement: .bottomBar) {
          Button {
            showURLInput = true
          } label: {
            Label("Paste URL", systemImage: "link")
          }

          Spacer()

          Button {
            showWebView = true
          } label: {
            Label("Browse YouTube", systemImage: "safari")
          }
        }
      }
      .navigationDestination(item: $selectedVideoItem) { videoItem in
        PlayerView(videoItem: videoItem)
          .navigationTransition(.zoom(sourceID: videoItem.videoID, in: heroNamespace))
      }
      .sheet(isPresented: $showWebView) {
        NavigationStack {
          YouTubeWebView { videoID in
            Task {
              try? await historyService.addToHistory(
                videoID: videoID,
                url: "https://www.youtube.com/watch?v=\(videoID)"
              )
              // Fetch the VideoItem to navigate to PlayerView
              let videoIDRaw = videoID.rawValue
              let descriptor = FetchDescriptor<VideoItem>(
                predicate: #Predicate { $0._videoID == videoIDRaw }
              )
              if let item = try? modelContext.fetch(descriptor).first {
                selectedVideoItem = item
              }
            }
            showWebView = false
          }
          .navigationTitle("YouTube")
          #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
          #endif
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") {
                showWebView = false
              }
            }
          }
        }
      }
      .onChange(of: deepLinkManager.pendingVideoID) { _, newVideoID in
        if let videoID = newVideoID {
          // Fetch the VideoItem for this videoID
          let videoIDRaw = videoID.rawValue
          let descriptor = FetchDescriptor<VideoItem>(
            predicate: #Predicate { $0._videoID == videoIDRaw }
          )
          if let item = try? modelContext.fetch(descriptor).first {
            selectedVideoItem = item
          }
          deepLinkManager.pendingVideoID = nil
        }
      }
      .sheet(isPresented: $showSettings) {
        SettingsView()
          .environment(vocabularyService)
      }
      .fittingSheet(isPresented: $showURLInput) {
        URLInputSheet { urlText in
          loadURL(urlText)
        }
      }
      .sheet(item: $videoToAddToPlaylist) { video in
        AddToPlaylistSheet(video: video)
      }
      .onDisappear { 
        
      }
    }
  }
  
  private func loadURL(_ urlText: String) {
    guard let url = URL(string: urlText), !urlText.isEmpty else {
      return
    }

    // Extract video ID and navigate to player
    if let videoID = YouTubeURLParser.extractVideoID(from: url) {
      Task {
        try? await historyService.addToHistory(videoID: videoID, url: urlText)
        // Fetch the VideoItem to navigate to PlayerView
        let videoIDRaw = videoID.rawValue
        let descriptor = FetchDescriptor<VideoItem>(
          predicate: #Predicate { $0._videoID == videoIDRaw }
        )
        if let item = try? modelContext.fetch(descriptor).first {
          await MainActor.run {
            selectedVideoItem = item
          }
        }
      }
    }
  }

  private func loadDemoVideo() {
    let demoVideoID: YouTubeContentID = "JKpsGXPqMd8"
    let demoURL = "https://www.youtube.com/watch?v=\(demoVideoID)"
    Task {
      try? await historyService.addToHistory(videoID: demoVideoID, url: demoURL)
      // Fetch the VideoItem to navigate to PlayerView
      let videoIDRaw = demoVideoID.rawValue
      let descriptor = FetchDescriptor<VideoItem>(
        predicate: #Predicate { $0._videoID == videoIDRaw }
      )
      if let item = try? modelContext.fetch(descriptor).first {
        await MainActor.run {
          selectedVideoItem = item
        }
      }
    }
  }
}

#Preview {
  HomeView()
}
