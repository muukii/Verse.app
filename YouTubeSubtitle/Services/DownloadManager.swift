//
//  DownloadManager.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/05.
//

@preconcurrency import BackgroundTasks
import Foundation
import SwiftData
import YouTubeKit

// MARK: - Download Progress

struct DownloadProgress: Sendable {
  let recordID: UUID
  let videoID: String
  let videoTitle: String?
  var fractionCompleted: Double
  var state: DownloadState
}

// MARK: - Download Error

enum DownloadError: LocalizedError {
  case invalidURL
  case taskExpired
  case noData
  case fileWriteFailed(any Error)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid download URL"
    case .taskExpired:
      return "Download was interrupted by the system"
    case .noData:
      return "No data received"
    case .fileWriteFailed(let error):
      return "Failed to save file: \(error.localizedDescription)"
    case .cancelled:
      return "Download was cancelled"
    }
  }
}

// MARK: - Download Manager

/// Manages video downloads using BGContinuedProcessingTask for background execution.
/// Progress is automatically displayed in Live Activity.
@Observable
@MainActor
final class DownloadManager: Sendable {

  // MARK: - Singleton

  static let shared = DownloadManager()

  // MARK: - Observable State

  /// Active downloads with their progress (for UI observation)
  private(set) var activeDownloads: [UUID: DownloadProgress] = [:]

  /// Pending downloads in queue
  private(set) var pendingRecordIDs: [UUID] = []

  // MARK: - Constants

  /// Static task identifier registered in Info.plist
  private static let taskIdentifier = "app.muukii.verse.download"

  // MARK: - Private Properties

  private let scheduler = BGTaskScheduler.shared
  private var modelContainer: ModelContainer?
  private var activeTask: BGContinuedProcessingTask?
  private var downloadTasks: [UUID: Task<Void, Never>] = [:]
  private var isTaskRegistered = false

  // MARK: - Initialization

  private init() {}

  // MARK: - Configuration

  /// Configure the manager with ModelContainer. Call this on app launch.
  func configure(modelContainer: ModelContainer) {
    self.modelContainer = modelContainer
    // Handlers are registered dynamically in submitTask(for:) for each download
  }

  /// Handle the background task for a specific download.
  private func handleBackgroundTask(_ task: BGContinuedProcessingTask, recordID: UUID) async {
    await executeDownload(task: task, recordID: recordID)
    task.setTaskCompleted(success: true)

    // Remove from pending
    pendingRecordIDs.removeAll { $0 == recordID }
  }

  /// Submit a task request for a specific download.
  private func submitTask(for recordID: UUID) throws {
    guard let progress = activeDownloads[recordID] else { return }

    let fullIdentifier = Self.taskIdentifier + ".\(recordID.uuidString)"

    // Dynamically register handler for this specific task identifier
    scheduler.register(forTaskWithIdentifier: fullIdentifier, using: nil) { @Sendable [weak self] task in
      
      guard let bgTask = task as? BGContinuedProcessingTask else {
        return
      }
      
      Task { @MainActor [weak self, bgTask] in
        await self?.handleBackgroundTask(bgTask, recordID: recordID)
      }
    }

    // Use video title if available, otherwise generic title
    let title = progress.videoTitle ?? "Downloading video"
    let subtitle = "YouTube: \(progress.videoID)"

    let request = BGContinuedProcessingTaskRequest(
      identifier: fullIdentifier,
      title: title,
      subtitle: subtitle
    )
    request.strategy = .queue

    try scheduler.submit(request)
  }

  // MARK: - Public API

  /// Queue a new download for the specified video and stream.
  /// Returns the record ID for tracking.
  @discardableResult
  func queueDownload(
    videoID: String,
    stream: YouTubeKit.Stream
  ) async throws -> UUID {
    guard let modelContainer else {
      fatalError("DownloadManager not configured. Call configure(modelContainer:) first.")
    }

    // Fetch video title from VideoHistoryItem
    let context = ModelContext(modelContainer)
    let historyDescriptor = FetchDescriptor<VideoHistoryItem>(
      predicate: #Predicate { $0.videoID == videoID }
    )
    let videoTitle = try? context.fetch(historyDescriptor).first?.title

    // Create download record
    let record = DownloadRecord(
      videoID: videoID,
      streamURL: stream.url.absoluteString,
      fileExtension: stream.fileExtension.rawValue,
      resolution: stream.videoResolution
    )

    // Save to SwiftData
    context.insert(record)
    try context.save()

    let recordID = record.id

    // Update observable state
    activeDownloads[recordID] = DownloadProgress(
      recordID: recordID,
      videoID: videoID,
      videoTitle: videoTitle,
      fractionCompleted: 0,
      state: .pending
    )
    pendingRecordIDs.append(recordID)

    // Try to submit BGTask, fall back to foreground download if unavailable
    do {
      try submitTask(for: recordID)
    } catch {
      // BGTask unavailable (e.g., simulator), run foreground download
      print("BGTask unavailable, falling back to foreground download: \(error)")
      startForegroundDownload(recordID: recordID)
    }

    return recordID
  }

  /// Start a foreground download when BGTask is unavailable.
  private func startForegroundDownload(recordID: UUID) {
    let downloadTask = Task { [weak self] in
      guard let self else { return }
      await self.performForegroundDownload(recordID: recordID)
    }
    downloadTasks[recordID] = downloadTask
  }

  /// Perform download in foreground (no BGTask).
  private func performForegroundDownload(recordID: UUID) async {
    guard let modelContainer else { return }

    // Fetch record
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<DownloadRecord>(
      predicate: #Predicate { $0.id == recordID }
    )
    guard let record = try? context.fetch(descriptor).first else { return }

    // Update state to downloading
    record.state = .downloading
    try? context.save()
    updateProgress(recordID: recordID, fraction: 0, state: .downloading)

    // Parse URL
    guard let url = URL(string: record.streamURL) else {
      await markFailed(recordID: recordID, error: DownloadError.invalidURL, context: context)
      return
    }

    do {
      // Download with progress (foreground version)
      let destinationURL = try await downloadWithProgressForeground(
        from: url,
        record: record,
        context: context
      )

      // Mark as completed
      record.state = .completed
      record.completedAt = Date()
      record.destinationFileName = destinationURL.lastPathComponent
      try? context.save()

      // Update VideoHistoryItem
      await updateVideoHistory(
        videoID: record.videoID,
        fileName: destinationURL.lastPathComponent
      )

      updateProgress(recordID: recordID, fraction: 1.0, state: .completed)
      pendingRecordIDs.removeAll { $0 == recordID }
      downloadTasks.removeValue(forKey: recordID)

      // Process next in queue
      if let nextID = pendingRecordIDs.first {
        startForegroundDownload(recordID: nextID)
      }

    } catch is CancellationError {
      record.state = .cancelled
      try? context.save()
      updateProgress(recordID: recordID, fraction: record.fractionCompleted, state: .cancelled)
      downloadTasks.removeValue(forKey: recordID)

    } catch {
      await markFailed(recordID: recordID, error: error, context: context)
      downloadTasks.removeValue(forKey: recordID)
    }
  }

  /// Download with progress tracking (foreground version without BGTask).
  private func downloadWithProgressForeground(
    from url: URL,
    record: DownloadRecord,
    context: ModelContext
  ) async throws -> URL {

    // Start download using URLSession.bytes for streaming progress
    let (bytes, response) = try await URLSession.shared.bytes(from: url)

    // Get expected content length
    let expectedLength = response.expectedContentLength
    if expectedLength > 0 {
      record.totalBytes = expectedLength
    }

    // Prepare destination file
    let fileName = "\(record.videoID).\(record.fileExtension)"
    let destinationURL = URL.documentsDirectory.appendingPathComponent(fileName)

    // Remove existing file if any
    try? FileManager.default.removeItem(at: destinationURL)

    // Create output stream
    guard let outputStream = OutputStream(url: destinationURL, append: false) else {
      throw DownloadError.fileWriteFailed(
        NSError(domain: "DownloadManager", code: -1, userInfo: [
          NSLocalizedDescriptionKey: "Failed to create output stream"
        ])
      )
    }
    outputStream.open()
    defer { outputStream.close() }

    var downloadedBytes: Int64 = 0
    var buffer = [UInt8](repeating: 0, count: 65536)  // 64KB buffer
    var lastProgressUpdate = Date()

    for try await byte in bytes {
      // Check for cancellation
      try Task.checkCancellation()

      buffer[Int(downloadedBytes % 65536)] = byte
      downloadedBytes += 1

      // Write buffer when full
      if downloadedBytes % 65536 == 0 {
        outputStream.write(buffer, maxLength: buffer.count)
      }

      // Update progress (throttled to avoid excessive updates)
      let now = Date()
      if now.timeIntervalSince(lastProgressUpdate) >= 0.5 {
        lastProgressUpdate = now

        let fraction: Double
        if expectedLength > 0 {
          fraction = Double(downloadedBytes) / Double(expectedLength)
        } else {
          fraction = 0
        }

        // Update record
        record.downloadedBytes = downloadedBytes
        try? context.save()

        // Update observable state
        await MainActor.run {
          updateProgress(recordID: record.id, fraction: fraction, state: .downloading)
        }
      }
    }

    // Write remaining bytes
    let remaining = Int(downloadedBytes % 65536)
    if remaining > 0 {
      outputStream.write(buffer, maxLength: remaining)
    }

    // Final progress update
    record.downloadedBytes = downloadedBytes
    record.totalBytes = downloadedBytes
    try? context.save()

    return destinationURL
  }

  /// Cancel a specific download.
  func cancelDownload(recordID: UUID) {
    // Cancel the download task
    downloadTasks[recordID]?.cancel()
    downloadTasks[recordID] = nil

    // Update state
    Task {
      await updateRecordState(recordID: recordID, state: .cancelled)
    }

    // Remove from active downloads
    activeDownloads.removeValue(forKey: recordID)
    pendingRecordIDs.removeAll { $0 == recordID }
  }

  /// Cancel all downloads for a specific video ID.
  /// Call this when deleting a VideoHistoryItem.
  func cancelDownloads(for videoID: String) {
    let recordsToCancel = activeDownloads.filter { $0.value.videoID == videoID }
    for (recordID, _) in recordsToCancel {
      cancelDownload(recordID: recordID)
    }
  }

  /// Get download progress for a specific video ID.
  func downloadProgress(for videoID: String) -> DownloadProgress? {
    activeDownloads.values.first { $0.videoID == videoID }
  }

  /// Restore pending downloads on app launch.
  /// Call this after configure(modelContainer:).
  func restorePendingDownloads() async {
    guard let modelContainer else { return }

    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<DownloadRecord>(
      predicate: #Predicate {
        $0.stateRawValue == "pending" || $0.stateRawValue == "downloading"
      }
    )

    guard let records = try? context.fetch(descriptor) else { return }

    for record in records {
      // Fetch video title from VideoHistoryItem
      // Capture videoID locally for #Predicate macro
      let targetVideoID = record.videoID
      let historyDescriptor = FetchDescriptor<VideoHistoryItem>(
        predicate: #Predicate { $0.videoID == targetVideoID }
      )
      let videoTitle = try? context.fetch(historyDescriptor).first?.title

      activeDownloads[record.id] = DownloadProgress(
        recordID: record.id,
        videoID: record.videoID,
        videoTitle: videoTitle,
        fractionCompleted: record.fractionCompleted,
        state: record.state
      )

      if record.state == .pending {
        pendingRecordIDs.append(record.id)
      }
    }

    // Submit tasks for all pending downloads (each gets unique wildcard identifier)
    for recordID in pendingRecordIDs {
      do {
        try submitTask(for: recordID)
      } catch {
        // BGTask unavailable, fall back to foreground download
        print("BGTask unavailable for restored download, falling back to foreground: \(error)")
        startForegroundDownload(recordID: recordID)
        break // Only start one foreground download at a time
      }
    }
  }

  // MARK: - Download Execution

  private func executeDownload(
    task: BGContinuedProcessingTask,
    recordID: UUID
  ) async {
    // Track active task
    activeTask = task

    // Set up expiration handler
    var wasExpired = false
    task.expirationHandler = { [weak self] in
      wasExpired = true
      Task { @MainActor in
        self?.downloadTasks[recordID]?.cancel()
      }
    }

    // Execute download
    let downloadTask = Task { [weak self] in
      guard let self else { return }
      await self.performDownload(
        task: task,
        recordID: recordID,
        checkExpired: { wasExpired }
      )
    }
    downloadTasks[recordID] = downloadTask

    await downloadTask.value

    // Cleanup
    activeTask = nil
    downloadTasks.removeValue(forKey: recordID)
  }

  private func performDownload(
    task: BGContinuedProcessingTask,
    recordID: UUID,
    checkExpired: @escaping () -> Bool
  ) async {
    guard let modelContainer else { return }

    // Fetch record
    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<DownloadRecord>(
      predicate: #Predicate { $0.id == recordID }
    )
    guard let record = try? context.fetch(descriptor).first else { return }

    // Update state to downloading
    record.state = .downloading
    try? context.save()
    updateProgress(recordID: recordID, fraction: 0, state: .downloading)

    // Parse URL
    guard let url = URL(string: record.streamURL) else {
      await markFailed(recordID: recordID, error: DownloadError.invalidURL, context: context)
      return
    }

    do {
      // Download with progress
      let destinationURL = try await downloadWithProgress(
        from: url,
        record: record,
        task: task,
        checkExpired: checkExpired,
        context: context
      )

      // Mark as completed
      record.state = .completed
      record.completedAt = Date()
      record.destinationFileName = destinationURL.lastPathComponent
      try? context.save()

      // Update VideoHistoryItem
      await updateVideoHistory(
        videoID: record.videoID,
        fileName: destinationURL.lastPathComponent
      )

      updateProgress(recordID: recordID, fraction: 1.0, state: .completed)
      pendingRecordIDs.removeAll { $0 == recordID }

    } catch is CancellationError {
      record.state = .cancelled
      try? context.save()
      updateProgress(recordID: recordID, fraction: record.fractionCompleted, state: .cancelled)

    } catch {
      await markFailed(recordID: recordID, error: error, context: context)
    }
  }

  private func downloadWithProgress(
    from url: URL,
    record: DownloadRecord,
    task: BGContinuedProcessingTask,
    checkExpired: @escaping () -> Bool,
    context: ModelContext
  ) async throws -> URL {

    // Configure progress reporting for Live Activity
    task.progress.totalUnitCount = 100

    // Start download using URLSession.bytes for streaming progress
    let (bytes, response) = try await URLSession.shared.bytes(from: url)

    // Get expected content length
    let expectedLength = response.expectedContentLength
    if expectedLength > 0 {
      record.totalBytes = expectedLength
    }

    // Prepare destination file
    let fileName = "\(record.videoID).\(record.fileExtension)"
    let destinationURL = URL.documentsDirectory.appendingPathComponent(fileName)

    // Remove existing file if any
    try? FileManager.default.removeItem(at: destinationURL)

    // Create output stream
    guard let outputStream = OutputStream(url: destinationURL, append: false) else {
      throw DownloadError.fileWriteFailed(
        NSError(domain: "DownloadManager", code: -1, userInfo: [
          NSLocalizedDescriptionKey: "Failed to create output stream"
        ])
      )
    }
    outputStream.open()
    defer { outputStream.close() }

    var downloadedBytes: Int64 = 0
    var buffer = [UInt8](repeating: 0, count: 65536)  // 64KB buffer
    var lastProgressUpdate = Date()

    for try await byte in bytes {
      // Check for cancellation or expiration
      try Task.checkCancellation()
      if checkExpired() {
        throw DownloadError.taskExpired
      }

      buffer[Int(downloadedBytes % 65536)] = byte
      downloadedBytes += 1

      // Write buffer when full
      if downloadedBytes % 65536 == 0 {
        outputStream.write(buffer, maxLength: buffer.count)
      }

      // Update progress (throttled to avoid excessive updates)
      let now = Date()
      if now.timeIntervalSince(lastProgressUpdate) >= 0.5 {
        lastProgressUpdate = now

        let fraction: Double
        if expectedLength > 0 {
          fraction = Double(downloadedBytes) / Double(expectedLength)
        } else {
          fraction = 0
        }

        // Update Live Activity progress
        task.progress.completedUnitCount = Int64(fraction * 100)
        task.updateTitle("Downloading video", subtitle: "\(Int(fraction * 100))%")

        // Update record
        record.downloadedBytes = downloadedBytes
        try? context.save()

        // Update observable state
        await MainActor.run {
          updateProgress(recordID: record.id, fraction: fraction, state: .downloading)
        }
      }
    }

    // Write remaining bytes
    let remaining = Int(downloadedBytes % 65536)
    if remaining > 0 {
      outputStream.write(buffer, maxLength: remaining)
    }

    // Final progress update
    record.downloadedBytes = downloadedBytes
    record.totalBytes = downloadedBytes
    try? context.save()

    return destinationURL
  }

  // MARK: - Helpers

  private func updateProgress(recordID: UUID, fraction: Double, state: DownloadState) {
    if var progress = activeDownloads[recordID] {
      progress.fractionCompleted = fraction
      progress.state = state
      activeDownloads[recordID] = progress
    }
  }

  private func markFailed(
    recordID: UUID,
    error: any Error,
    context: ModelContext
  ) async {
    let descriptor = FetchDescriptor<DownloadRecord>(
      predicate: #Predicate { $0.id == recordID }
    )
    if let record = try? context.fetch(descriptor).first {
      record.state = .failed
      record.errorMessage = error.localizedDescription
      try? context.save()
    }

    updateProgress(recordID: recordID, fraction: 0, state: .failed)
    pendingRecordIDs.removeAll { $0 == recordID }
  }

  private func updateRecordState(recordID: UUID, state: DownloadState) async {
    guard let modelContainer else { return }

    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<DownloadRecord>(
      predicate: #Predicate { $0.id == recordID }
    )
    if let record = try? context.fetch(descriptor).first {
      record.state = state
      try? context.save()
    }
  }

  private func updateVideoHistory(videoID: String, fileName: String) async {
    guard let modelContainer else { return }

    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<VideoHistoryItem>(
      predicate: #Predicate { $0.videoID == videoID }
    )
    if let historyItem = try? context.fetch(descriptor).first {
      historyItem.downloadedFileName = fileName
      try? context.save()
    }
  }
}
