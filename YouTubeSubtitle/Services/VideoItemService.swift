//
//  VideoItemService.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/06.
//

import Foundation
import SwiftData

/// Service for managing video items and their associated resources.
/// Centralizes operations on VideoItem to ensure proper cleanup of files and data.
@Observable
@MainActor
final class VideoItemService {

  private let modelContext: ModelContext
  private let downloadManager: DownloadManager

  init(modelContext: ModelContext, downloadManager: DownloadManager) {
    self.modelContext = modelContext
    self.downloadManager = downloadManager
  }

  // MARK: - Add to History

  /// Add a video to history with metadata.
  /// Removes any existing entry for the same videoID to prevent duplicates.
  /// Keeps only the most recent 50 items.
  func addToHistory(videoID: YouTubeContentID, url: String) async throws {
    // Fetch metadata
    let metadata = await VideoMetadataFetcher.fetch(videoID: videoID)

    // Fetch all history items
    let descriptor = FetchDescriptor<VideoItem>(
      sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    let history = try modelContext.fetch(descriptor)

    // Remove existing items with same videoID
    let existingItems = history.filter { $0.videoID == videoID }
    for item in existingItems {
      modelContext.delete(item)
    }

    // Insert new item
    let newItem = VideoItem(
      videoID: videoID,
      url: url,
      title: metadata.title,
      author: metadata.author,
      thumbnailURL: metadata.thumbnailURL
    )
    modelContext.insert(newItem)

    // Keep only most recent 50 items
    if history.count > 50 {
      let itemsToDelete = history.suffix(history.count - 50)
      for item in itemsToDelete {
        try await deleteHistoryItem(item)
      }
    }

    try modelContext.save()
  }

  // MARK: - Delete History Item

  /// Delete a video item and clean up all associated resources:
  /// - Cancels any active downloads
  /// - Deletes local video file if exists
  /// - Removes from SwiftData
  func deleteHistoryItem(_ item: VideoItem) async throws {
    // 1. Cancel any active downloads
    downloadManager.cancelDownloads(for: item.videoID)

    // 2. Delete local video file if exists
    if let fileURL = item.downloadedFileURL {
      try? FileManager.default.removeItem(at: fileURL)
    }

    // 3. Delete from SwiftData
    modelContext.delete(item)

    try modelContext.save()
  }

  /// Delete multiple video items at once.
  func deleteHistoryItems(_ items: [VideoItem]) async throws {
    for item in items {
      // Cancel downloads and delete files
      downloadManager.cancelDownloads(for: item.videoID)
      if let fileURL = item.downloadedFileURL {
        try? FileManager.default.removeItem(at: fileURL)
      }
      modelContext.delete(item)
    }

    try modelContext.save()
  }

  // MARK: - Clear All History

  /// Clear all video items and their associated resources.
  func clearAllHistory() async throws {
    let descriptor = FetchDescriptor<VideoItem>()
    let allItems = try modelContext.fetch(descriptor)

    try await deleteHistoryItems(allItems)
  }

  // MARK: - Delete Local Video

  /// Delete the local video file for a specific video item.
  /// Updates the downloadedFileName to nil in the database.
  func deleteLocalVideo(for item: VideoItem) throws {
    guard let fileURL = item.downloadedFileURL else { return }

    // Delete the file
    try FileManager.default.removeItem(at: fileURL)

    // Update database
    item.downloadedFileName = nil

    try modelContext.save()
  }

  // MARK: - Update Subtitles

  /// Update cached subtitles for a video.
  func updateCachedSubtitles(videoID: YouTubeContentID, subtitles: Subtitle) throws {
    let videoIDRaw = videoID.rawValue
    let descriptor = FetchDescriptor<VideoItem>(
      predicate: #Predicate { $0._videoID == videoIDRaw }
    )

    guard let item = try modelContext.fetch(descriptor).first else {
      throw VideoItemError.itemNotFound
    }

    item.cachedSubtitles = subtitles

    try modelContext.save()
  }

  // MARK: - Update Playback Position

  /// Update playback position for a video to enable resume functionality.
  /// - Parameters:
  ///   - videoID: The video ID to update
  ///   - position: Current playback position in seconds. Pass nil to clear the position.
  func updatePlaybackPosition(videoID: YouTubeContentID, position: Double?) throws {
    let videoIDRaw = videoID.rawValue
    let descriptor = FetchDescriptor<VideoItem>(
      predicate: #Predicate { $0._videoID == videoIDRaw }
    )

    guard let item = try modelContext.fetch(descriptor).first else {
      throw VideoItemError.itemNotFound
    }

    item.lastPlaybackPosition = position

    try modelContext.save()
  }

  // MARK: - Find Item

  /// Find a video item by videoID.
  func findItem(videoID: YouTubeContentID) throws -> VideoItem? {
    let videoIDRaw = videoID.rawValue
    let descriptor = FetchDescriptor<VideoItem>(
      predicate: #Predicate { $0._videoID == videoIDRaw }
    )
    return try modelContext.fetch(descriptor).first
  }

  // MARK: - Playlist Management

  /// Create a new playlist with the given name.
  @discardableResult
  func createPlaylist(name: String) throws -> Playlist {
    let playlist = Playlist(name: name)
    modelContext.insert(playlist)
    try modelContext.save()
    return playlist
  }

  /// Update a playlist's name.
  func updatePlaylist(_ playlist: Playlist, name: String) throws {
    playlist.name = name
    playlist.updatedAt = Date()
    try modelContext.save()
  }

  /// Delete a playlist and all its entries.
  func deletePlaylist(_ playlist: Playlist) throws {
    modelContext.delete(playlist)
    try modelContext.save()
  }

  // MARK: - Playlist Entry Management

  /// Add a video to a playlist.
  /// Returns true if added, false if already in playlist.
  @discardableResult
  func addVideo(_ video: VideoItem, to playlist: Playlist) throws -> Bool {
    let isAlreadyInPlaylist = playlist.entries.contains { $0.video?.id == video.id }
    guard !isAlreadyInPlaylist else { return false }

    let order = playlist.entries.count
    let entry = PlaylistEntry(playlist: playlist, video: video, order: order)

    modelContext.insert(entry)
    playlist.updatedAt = Date()
    try modelContext.save()

    return true
  }

  /// Remove a video from a playlist.
  func removeVideo(_ video: VideoItem, from playlist: Playlist) throws {
    guard let entry = playlist.entries.first(where: { $0.video?.id == video.id }) else {
      return
    }

    let removedOrder = entry.order
    modelContext.delete(entry)

    for remainingEntry in playlist.entries where remainingEntry.order > removedOrder {
      remainingEntry.order -= 1
    }

    playlist.updatedAt = Date()
    try modelContext.save()
  }

  /// Reorder videos in a playlist (for drag and drop).
  func reorderVideos(in playlist: Playlist, from source: IndexSet, to destination: Int) throws {
    var entries = playlist.entries.sorted { $0.order < $1.order }

    let itemsToMove = source.map { entries[$0] }

    for index in source.sorted().reversed() {
      entries.remove(at: index)
    }

    let adjustedDestination = destination - source.filter { $0 < destination }.count

    for (offset, item) in itemsToMove.enumerated() {
      entries.insert(item, at: adjustedDestination + offset)
    }

    for (index, entry) in entries.enumerated() {
      entry.order = index
    }

    playlist.updatedAt = Date()
    try modelContext.save()
  }

  /// Check if a video is in a specific playlist.
  func isVideo(_ video: VideoItem, in playlist: Playlist) -> Bool {
    playlist.entries.contains { $0.video?.id == video.id }
  }
}

// MARK: - Error

enum VideoItemError: LocalizedError {
  case itemNotFound

  var errorDescription: String? {
    switch self {
    case .itemNotFound:
      return "Video history item not found"
    }
  }
}
