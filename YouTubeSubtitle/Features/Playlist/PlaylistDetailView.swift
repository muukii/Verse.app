//
//  PlaylistDetailView.swift
//  YouTubeSubtitle
//

import SwiftUI
import SwiftData
import AsyncMultiplexImage
import AsyncMultiplexImage_Nuke

struct PlaylistDetailView: View {
  @Bindable var playlist: Playlist
  @Environment(VideoItemService.self) private var historyService
  @Environment(\.editMode) private var editMode

  @State private var selectedVideoItem: VideoItem?
  @State private var showRenameAlert: Bool = false
  @State private var newName: String = ""

  private var sortedVideos: [VideoItem] {
    playlist.videos
  }

  var body: some View {
    Group {
      if sortedVideos.isEmpty {
        emptyStateView
      } else {
        listView
      }
    }
    .navigationTitle(playlist.name)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        EditButton()
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          newName = playlist.name
          showRenameAlert = true
        } label: {
          Label("Rename", systemImage: "pencil")
        }
      }
    }
    .navigationDestination(item: $selectedVideoItem) { videoItem in
      PlayerView(videoItem: videoItem)
    }
    .alert("Rename Playlist", isPresented: $showRenameAlert) {
      TextField("Playlist name", text: $newName)
      Button("Cancel", role: .cancel) {}
      Button("Save") {
        if !newName.isEmpty {
          try? historyService.updatePlaylist(playlist, name: newName)
        }
      }
    }
  }

  // MARK: - Empty State

  private var emptyStateView: some View {
    ContentUnavailableView {
      Label("No Videos", systemImage: "film.stack")
    } description: {
      Text("Add videos to this playlist from\nthe video history.")
    }
  }

  // MARK: - List View

  private var listView: some View {
    List {
      ForEach(sortedVideos) { video in
        Button {
          selectedVideoItem = video
        } label: {
          PlaylistVideoCell(video: video)
        }
        .buttonStyle(.plain)
      }
      .onDelete(perform: deleteVideos)
      .onMove(perform: moveVideos)
    }
    .listStyle(.inset)
  }

  // MARK: - Actions

  private func deleteVideos(at offsets: IndexSet) {
    let videosToRemove = offsets.map { sortedVideos[$0] }
    for video in videosToRemove {
      try? historyService.removeVideo(video, from: playlist)
    }
  }

  private func moveVideos(from source: IndexSet, to destination: Int) {
    try? historyService.reorderVideos(in: playlist, from: source, to: destination)
  }
}

// MARK: - Playlist Video Cell

struct PlaylistVideoCell: View {
  let video: VideoItem

  /// Playback progress (0.0 to 1.0) for progress bar display
  private var playbackProgress: Double? {
    guard let position = video.lastPlaybackPosition,
          let duration = video.duration,
          duration > 0 else { return nil }
    return min(max(position / duration, 0), 1)
  }

  var body: some View {
    HStack(spacing: 12) {
      // Thumbnail
      thumbnailView

      // Info
      VStack(alignment: .leading, spacing: 4) {
        Text(video.title ?? "Untitled")
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)

        if let author = video.author {
          Text(author)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var thumbnailView: some View {
    if let thumbnailURL = video.thumbnailURL.flatMap({ URL(string: $0) }) {
      AsyncMultiplexImageNuke(
        imageRepresentation: .remote(.init(constant: thumbnailURL))
      )
      .aspectRatio(contentMode: .fill)
      .frame(width: 80, height: 45)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(alignment: .bottom) {
        playbackProgressBar
      }
    } else {
      Rectangle()
        .fill(Color.gray.opacity(0.2))
        .overlay {
          Image(systemName: "play.rectangle.fill")
            .foregroundStyle(.tertiary)
        }
        .frame(width: 80, height: 45)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) {
          playbackProgressBar
        }
    }
  }

  @ViewBuilder
  private var playbackProgressBar: some View {
    if let progress = playbackProgress {
      GeometryReader { geometry in
        Rectangle()
          .fill(Color.red)
          .frame(width: geometry.size.width * progress, height: 3)
      }
      .frame(height: 3)
      .clipShape(
        UnevenRoundedRectangle(
          bottomLeadingRadius: 6,
          bottomTrailingRadius: progress >= 0.99 ? 6 : 0
        )
      )
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    PlaylistDetailView(playlist: Playlist(name: "Preview Playlist"))
  }
}
