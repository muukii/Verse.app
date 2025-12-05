//
//  VideoHistoryService.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/06.
//

import Foundation
import SwiftData
import SwiftSubtitles

/// Service for managing video items and their associated resources.
/// Centralizes operations on VideoItem to ensure proper cleanup of files and data.
@Observable
@MainActor
final class VideoHistoryService {

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
  func addToHistory(videoID: String, url: String) async throws {
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
  func updateCachedSubtitles(videoID: String, subtitles: Subtitles) throws {
    let descriptor = FetchDescriptor<VideoItem>(
      predicate: #Predicate { $0.videoID == videoID }
    )

    guard let item = try modelContext.fetch(descriptor).first else {
      throw VideoHistoryError.itemNotFound
    }

    item.cachedSubtitles = subtitles

    try modelContext.save()
  }

  // MARK: - Find Item

  /// Find a video item by videoID.
  func findItem(videoID: String) throws -> VideoItem? {
    let descriptor = FetchDescriptor<VideoItem>(
      predicate: #Predicate { $0.videoID == videoID }
    )
    return try modelContext.fetch(descriptor).first
  }
}

// MARK: - Error

enum VideoHistoryError: LocalizedError {
  case itemNotFound

  var errorDescription: String? {
    switch self {
    case .itemNotFound:
      return "Video history item not found"
    }
  }
}
