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
  @Query(sort: \VideoHistoryItem.timestamp, order: .reverse) private var history: [VideoHistoryItem]

  @State private var selectedVideoID: String?
  @State private var showWebView: Bool = false
  @State private var showSettings: Bool = false
  @State private var showURLInput: Bool = false
  @ObservedObject private var deepLinkManager = DeepLinkManager.shared

  @Namespace private var heroNamespace

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // URL Input Button
        Button {
          showURLInput = true
        } label: {
          Label("Paste URL", systemImage: "link")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        // History List
        if history.isEmpty {
          ContentUnavailableView {
            Label("Verse", systemImage: "captions.bubble.fill")
          } description: {
            Text("Watch YouTube videos with synced subtitles.\nPaste a URL above or browse YouTube to get started.")
          } actions: {
            VStack(spacing: 12) {
              Button {
                showWebView = true
              } label: {
                Text("Browse YouTube")
              }
              .buttonStyle(.borderedProminent)

              Button {
                loadDemoVideo()
              } label: {
                Label("Try Demo Video", systemImage: "play.circle")
              }
              .buttonStyle(.bordered)
            }
          }
        } else {
          List {
            ForEach(history) { item in
              Button {
                selectedVideoID = item.videoID
              } label: {
                VideoHistoryCell(
                  item: item,
                  namespace: heroNamespace
                )
              }
              .buttonStyle(.plain)
            }
            .onDelete { indexSet in
              for index in indexSet {
                modelContext.delete(history[index])
              }
            }
          }
          .listStyle(.inset)
        }
      }
      .navigationTitle("")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showWebView = true
          } label: {
            Label("Browse YouTube", systemImage: "safari")
          }
        }
        ToolbarItem(placement: .secondaryAction) {
          Button {
            showSettings = true
          } label: {
            Label("Settings", systemImage: "gear")
          }
        }
        if !history.isEmpty {
          ToolbarItem(placement: .secondaryAction) {
            Button(role: .destructive) {
              clearHistory()
            } label: {
              Label("Clear History", systemImage: "trash")
            }
          }
        }
      }
      .navigationDestination(item: $selectedVideoID) { videoID in
        PlayerView(videoID: videoID)
          .navigationTransition(.zoom(sourceID: videoID, in: heroNamespace))
      }
      .sheet(isPresented: $showWebView) {
        NavigationStack {
          YouTubeWebView { videoID in
            Task {
              await addToHistory(videoID: videoID, url: "https://www.youtube.com/watch?v=\(videoID)")
            }
            showWebView = false
            selectedVideoID = videoID
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
          selectedVideoID = videoID
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
        await addToHistory(videoID: videoID, url: urlText)
      }
      selectedVideoID = videoID
    }
  }

  private func loadDemoVideo() {
    let demoVideoID = "JKpsGXPqMd8"
    let demoURL = "https://www.youtube.com/watch?v=\(demoVideoID)"
    Task {
      await addToHistory(videoID: demoVideoID, url: demoURL)
    }
    selectedVideoID = demoVideoID
  }
  
  private func addToHistory(videoID: String, url: String) async {
    // メタデータを取得
    let metadata = await VideoMetadataFetcher.fetch(videoID: videoID)
    
    // 既存の同じvideoIDを削除（重複防止）
    let existingItems = history.filter { $0.videoID == videoID }
    for item in existingItems {
      modelContext.delete(item)
    }
    
    // 新しいアイテムを追加
    let newItem = VideoHistoryItem(
      videoID: videoID,
      url: url,
      title: metadata.title,
      author: metadata.author,
      thumbnailURL: metadata.thumbnailURL
    )
    modelContext.insert(newItem)
    
    // 最大50件を超えたら古いものを削除
    if history.count > 50 {
      let itemsToDelete = history.suffix(history.count - 50)
      for item in itemsToDelete {
        modelContext.delete(item)
      }
    }
  }
  
  private func clearHistory() {
    for item in history {
      modelContext.delete(item)
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
  let item: VideoHistoryItem
  let namespace: Namespace.ID

  var body: some View {
    HStack(spacing: 12) {
      // サムネイル画像
      thumbnailView

      // テキスト情報
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title ?? item.videoID)
          .font(.headline)
          .lineLimit(2)

        if let author = item.author {
          Text(author)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Text(formatDate(item.timestamp))
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .contentShape(Rectangle())
    .matchedTransitionSource(id: item.videoID, in: namespace)
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

#Preview {
  HomeView()
}
