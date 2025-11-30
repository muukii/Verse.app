//
//  HomeView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import SwiftData

struct HomeView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \VideoHistoryItem.timestamp, order: .reverse) private var history: [VideoHistoryItem]
  
  @State private var urlText: String = ""
  @State private var selectedVideoID: String?
  @ObservedObject private var deepLinkManager = DeepLinkManager.shared
  
  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // URL Input Section
        VStack(spacing: 12) {
          HStack {
            TextField("Enter YouTube URL", text: $urlText)
              .textFieldStyle(.roundedBorder)
              .onSubmit {
                loadURL()
              }
            
            Button("Load") {
              loadURL()
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlText.isEmpty)
          }
          .padding()
        }
        .background(Color(white: 0.95))
        
        Divider()
        
        // History List
        if history.isEmpty {
          VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "play.rectangle.fill")
              .font(.system(size: 60))
              .foregroundStyle(.blue)
            
            Text("YouTube Subtitle Player")
              .font(.largeTitle)
              .fontWeight(.bold)
            
            Text("Enter a YouTube URL to get started")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            
            Spacer()
          }
        } else {
          List {
            ForEach(history) { item in
              Button {
                selectedVideoID = item.videoID
              } label: {
                HStack(spacing: 12) {
                  // サムネイル画像
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
      .navigationTitle("YouTube Subtitle")
      .toolbar {
        if !history.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            Button {
              clearHistory()
            } label: {
              Label("Clear History", systemImage: "trash")
            }
          }
        }
      }
      .navigationDestination(item: $selectedVideoID) { videoID in
        PlayerView(videoID: videoID)
      }
      .onChange(of: deepLinkManager.pendingVideoID) { _, newVideoID in
        if let videoID = newVideoID {
          selectedVideoID = videoID
          deepLinkManager.pendingVideoID = nil
        }
      }
    }
  }
  
  private func loadURL() {
    guard let url = URL(string: urlText), !urlText.isEmpty else {
      return
    }
    
    // Extract video ID and navigate to player
    if let videoID = YouTubeURLParser.extractVideoID(from: url) {
      Task {
        await addToHistory(videoID: videoID, url: urlText)
      }
      selectedVideoID = videoID
      urlText = ""
    }
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

#Preview {
  HomeView()
}
