//
//  DownloadRecord.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/05.
//

import Foundation
import SwiftData

// MARK: - Download State

enum DownloadState: String, Codable, Sendable {
  case pending
  case downloading
  case completed
  case failed
  case cancelled
}

// MARK: - Download Record

/// SwiftData model for persistent download state.
/// Tracks download progress, state, and metadata for background downloads.
@Model
final class DownloadRecord {

  // MARK: - Identifiers

  @Attribute(.unique) var id: UUID

  /// The YouTube video ID
  var videoID: String

  // MARK: - Stream Info

  /// The URL to download from
  var streamURL: String

  /// File extension (mp4, webm, etc.)
  var fileExtension: String

  /// Video resolution in pixels (e.g., 720, 1080)
  var resolution: Int?

  // MARK: - Progress

  /// Total bytes to download (0 if unknown)
  var totalBytes: Int64

  /// Bytes downloaded so far
  var downloadedBytes: Int64

  /// Download state
  var stateRawValue: String

  var state: DownloadState {
    get { DownloadState(rawValue: stateRawValue) ?? .pending }
    set { stateRawValue = newValue.rawValue }
  }

  // MARK: - Result

  /// Destination file name (relative to Documents directory)
  var destinationFileName: String?

  // MARK: - Timestamps

  var createdAt: Date
  var completedAt: Date?

  // MARK: - Error

  var errorMessage: String?

  // MARK: - Computed Properties

  /// Progress fraction (0.0 to 1.0)
  var fractionCompleted: Double {
    guard totalBytes > 0 else { return 0 }
    return Double(downloadedBytes) / Double(totalBytes)
  }

  /// Destination file URL (if downloaded)
  var destinationFileURL: URL? {
    guard let fileName = destinationFileName else { return nil }
    return URL.documentsDirectory.appendingPathComponent(fileName)
  }

  // MARK: - Initialization

  init(
    videoID: String,
    streamURL: String,
    fileExtension: String,
    resolution: Int? = nil
  ) {
    self.id = UUID()
    self.videoID = videoID
    self.streamURL = streamURL
    self.fileExtension = fileExtension
    self.resolution = resolution
    self.totalBytes = 0
    self.downloadedBytes = 0
    self.stateRawValue = DownloadState.pending.rawValue
    self.createdAt = Date()
  }
}
