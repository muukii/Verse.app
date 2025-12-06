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
  @Environment(VideoHistoryService.self) private var historyService
  @Environment(DownloadManager.self) private var downloadManager
  @Query(sort: \VideoItem.timestamp, order: .reverse) private var history: [VideoItem]

  @State private var selectedVideoItem: VideoItem?
  @State private var showWebView: Bool = false
  @State private var showSettings: Bool = false
  @State private var showURLInput: Bool = false
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
                VideoHistoryCell(
                  item: item,
                  namespace: heroNamespace,
                  downloadManager: downloadManager
                )
              }
              .buttonStyle(.plain)
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
      }
      .fittingSheet(isPresented: $showURLInput) {
        URLInputSheet { urlText in
          loadURL(urlText)
        }
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
  
  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Video History Cell

struct VideoHistoryCell: View {
  let item: VideoItem
  let namespace: Namespace.ID
  let downloadManager: DownloadManager

  /// Download progress from DownloadManager
  private var downloadProgress: DownloadProgress? {
    downloadManager.downloadProgress(for: item.videoID)
  }

  var body: some View {
    HStack(spacing: 12) {
      // サムネイル画像
      thumbnailView
        .overlay(alignment: .bottomTrailing) {
          downloadStatusBadge
        }

      // テキスト情報
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title ?? item.videoID.rawValue)
          .font(.headline)
          .lineLimit(2)

        if let author = item.author {
          Text(author)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        HStack(spacing: 6) {
          Text(formatDate(item.timestamp))
            .font(.caption2)
            .foregroundStyle(.tertiary)

          // Show download status text (only for active downloads)
          if let progress = downloadProgress {
            downloadStatusText(for: progress)
          }
          // Note: Already downloaded state is shown via badge only (no redundant text)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .contentShape(Rectangle())
    .matchedTransitionSource(id: item.videoID, in: namespace)
  }

  @ViewBuilder
  private var downloadStatusBadge: some View {
    if let progress = downloadProgress {
      switch progress.state {
      case .pending, .downloading:
        // Circular progress indicator
        ZStack {
          Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 28, height: 28)
          CircularProgressView(progress: progress.fractionCompleted)
            .frame(width: 20, height: 20)
        }
        .padding(4)

      case .completed:
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(.green)
          .background(Circle().fill(.white).padding(2))
          .padding(4)

      case .paused:
        // Paused indicator
        Image(systemName: "pause.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(.gray)
          .background(Circle().fill(.white).padding(2))
          .padding(4)

      case .failed, .cancelled:
        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(.orange)
          .background(Circle().fill(.white).padding(2))
          .padding(4)
      }
    } else if item.isDownloaded {
      // Already downloaded (persisted)
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 20))
        .foregroundStyle(.green)
        .background(Circle().fill(.white).padding(2))
        .padding(4)
    }
  }

  @ViewBuilder
  private func downloadStatusText(for progress: DownloadProgress) -> some View {
    switch progress.state {
    case .pending:
      Text("Pending...")
        .font(.caption2)
        .foregroundStyle(.secondary)
    case .downloading:
      Text("Downloading \(Int(progress.fractionCompleted * 100))%")
        .font(.caption2)
        .foregroundStyle(.blue)
    case .completed:
      Text("Downloaded")
        .font(.caption2)
        .foregroundStyle(.green)
    case .failed:
      Text("Failed")
        .font(.caption2)
        .foregroundStyle(.red)
    case .cancelled:
      Text("Cancelled")
        .font(.caption2)
        .foregroundStyle(.orange)
    case .paused:
      Text("Paused")
        .font(.caption2)
        .foregroundStyle(.gray)
    }
  }

  @ViewBuilder
  private var thumbnailView: some View {
    if let thumbnailURLString = item.thumbnailURL,
       let thumbnailURL = URL(string: thumbnailURLString) {
      AsyncImage(url: thumbnailURL) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Rectangle()
          .fill(Color.gray.opacity(0.3))
      }
      .frame(width: 120, height: 68)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    } else {
      Rectangle()
        .fill(Color.gray.opacity(0.3))
        .frame(width: 120, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
          Image(systemName: "play.rectangle")
            .foregroundStyle(.white)
            .font(.title)
        }
    }
  }

  private func formatDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

// MARK: - Circular Progress View

private struct CircularProgressView: View {
  let progress: Double

  var body: some View {
    ZStack {
      // Background circle
      Circle()
        .stroke(Color.gray.opacity(0.3), lineWidth: 3)

      // Progress circle
      Circle()
        .trim(from: 0, to: progress)
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(.linear(duration: 0.3), value: progress)
    }
  }
}

#Preview {
  HomeView()
}
