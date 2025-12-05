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

// MARK: - Download Session Delegate

/// Handles URLSessionDownloadTask delegate callbacks and bridges to async/await.
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

  struct ProgressUpdate: Sendable {
    let bytesWritten: Int64
    let totalBytesWritten: Int64
    let totalBytesExpectedToWrite: Int64

    var fractionCompleted: Double {
      guard totalBytesExpectedToWrite > 0 else { return 0 }
      return Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    }
  }

  enum DownloadEvent: Sendable {
    case progress(ProgressUpdate)
    case completed(URL)
    case failed(any Error)
  }

  private let continuation: AsyncStream<DownloadEvent>.Continuation
  private let destinationURL: URL

  init(continuation: AsyncStream<DownloadEvent>.Continuation, destinationURL: URL) {
    self.continuation = continuation
    self.destinationURL = destinationURL
    super.init()
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let update = ProgressUpdate(
      bytesWritten: bytesWritten,
      totalBytesWritten: totalBytesWritten,
      totalBytesExpectedToWrite: totalBytesExpectedToWrite
    )
    continuation.yield(.progress(update))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // IMPORTANT: Must move file immediately - temp file is deleted when this method returns
    do {
      // Remove existing file if any
      try? FileManager.default.removeItem(at: destinationURL)
      try FileManager.default.moveItem(at: location, to: destinationURL)
      continuation.yield(.completed(destinationURL))
    } catch {
      continuation.yield(.failed(DownloadError.fileWriteFailed(error)))
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let error {
      continuation.yield(.failed(error))
    }
    continuation.finish()
  }
}

// MARK: - Download Manager

/// Manages video downloads using BGContinuedProcessingTask for background execution.
/// Progress is automatically displayed in Live Activity.
@Observable
@MainActor
final class DownloadManager: Sendable {

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
  private var urlSessionTasks: [UUID: URLSessionDownloadTask] = [:]
  private var isTaskRegistered = false

  // MARK: - Initialization

  init() {}

  // MARK: - Configuration

  /// Configure the manager with ModelContainer. Call this on app launch.
  func configure(modelContainer: ModelContainer) {
    self.modelContainer = modelContainer
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
      startDownload(recordID: recordID, bgTask: nil)
    }

    return recordID
  }

  /// Cancel a specific download.
  func cancelDownload(recordID: UUID) {
    // Cancel the URLSession download task
    urlSessionTasks[recordID]?.cancel()
    urlSessionTasks[recordID] = nil

    // Cancel the Swift Task
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

  /// Pause a specific download and save resume data.
  func pauseDownload(recordID: UUID) {
    guard let urlTask = urlSessionTasks[recordID] else { return }

    // Cancel with resume data
    urlTask.cancel { [weak self] resumeDataOrNil in
      Task { @MainActor [weak self] in
        guard let self else { return }

        // Cancel the Swift Task
        self.downloadTasks[recordID]?.cancel()
        self.downloadTasks[recordID] = nil
        self.urlSessionTasks[recordID] = nil

        // Save resume data to persistent storage
        await self.saveResumeData(recordID: recordID, resumeData: resumeDataOrNil)

        // Update observable state
        if var progress = self.activeDownloads[recordID] {
          progress.state = .paused
          self.activeDownloads[recordID] = progress
        }

        // Remove from pending
        self.pendingRecordIDs.removeAll { $0 == recordID }
      }
    }
  }

  /// Resume a paused download.
  func resumeDownload(recordID: UUID) {
    guard let modelContainer else { return }

    // Check if already downloading
    if downloadTasks[recordID] != nil { return }

    Task {
      let context = ModelContext(modelContainer)
      let descriptor = FetchDescriptor<DownloadRecord>(
        predicate: #Predicate { $0.id == recordID }
      )
      guard let record = try? context.fetch(descriptor).first else { return }

      // Check if we have resume data
      if let resumeData = record.resumeData {
        // Resume with saved data
        startDownloadWithResumeData(
          recordID: recordID,
          resumeData: resumeData,
          bgTask: nil
        )
      } else {
        // No resume data, start from beginning
        startDownload(recordID: recordID, bgTask: nil)
      }

      // Update state
      record.state = .downloading
      record.resumeData = nil  // Clear resume data
      try? context.save()

      // Update observable state
      if var progress = activeDownloads[recordID] {
        progress.state = .downloading
        activeDownloads[recordID] = progress
      }
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

    // Submit tasks for all pending downloads
    for recordID in pendingRecordIDs {
      do {
        try submitTask(for: recordID)
      } catch {
        // BGTask unavailable, fall back to foreground download
        print("BGTask unavailable for restored download, falling back to foreground: \(error)")
        startDownload(recordID: recordID, bgTask: nil)
        break // Only start one foreground download at a time
      }
    }
  }

  // MARK: - BGTask Management

  /// Handle the background task for a specific download.
  private func handleBackgroundTask(_ task: BGContinuedProcessingTask, recordID: UUID) async {
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

    // Configure progress reporting for Live Activity
    task.progress.totalUnitCount = 100

    // Execute download
    startDownload(recordID: recordID, bgTask: task, checkExpired: { wasExpired })

    // Wait for download to complete
    await downloadTasks[recordID]?.value

    // Cleanup
    activeTask = nil
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
      guard let bgTask = task as? BGContinuedProcessingTask else { return }

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

  // MARK: - Unified Download Execution

  /// Start a download task (unified for both foreground and BGTask).
  private func startDownload(
    recordID: UUID,
    bgTask: BGContinuedProcessingTask?,
    checkExpired: @escaping () -> Bool = { false }
  ) {
    let downloadTask = Task { [weak self] in
      guard let self else { return }
      await self.performDownload(
        recordID: recordID,
        bgTask: bgTask,
        checkExpired: checkExpired
      )
    }
    downloadTasks[recordID] = downloadTask
  }

  /// Perform the download (unified for both foreground and BGTask).
  private func performDownload(
    recordID: UUID,
    bgTask: BGContinuedProcessingTask?,
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
      // Download with progress using URLSessionDownloadTask
      let destinationURL = try await downloadFile(
        from: url,
        record: record,
        context: context,
        bgTask: bgTask,
        checkExpired: checkExpired
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

      // Remove from active downloads - UI will now use item.downloadedFileName
      activeDownloads.removeValue(forKey: recordID)
      pendingRecordIDs.removeAll { $0 == recordID }
      downloadTasks.removeValue(forKey: recordID)

      // Process next in queue (only for foreground downloads)
      if bgTask == nil, let nextID = pendingRecordIDs.first {
        startDownload(recordID: nextID, bgTask: nil)
      }

    } catch is CancellationError {
      record.state = .cancelled
      try? context.save()
      activeDownloads.removeValue(forKey: recordID)
      downloadTasks.removeValue(forKey: recordID)

    } catch {
      await markFailed(recordID: recordID, error: error, context: context)
      downloadTasks.removeValue(forKey: recordID)
    }
  }

  /// Download file using URLSessionDownloadTask (efficient, runs in background).
  private func downloadFile(
    from url: URL,
    record: DownloadRecord,
    context: ModelContext,
    bgTask: BGContinuedProcessingTask?,
    checkExpired: @escaping () -> Bool
  ) async throws -> URL {

    // Prepare destination file path
    let fileName = "\(record.videoID).\(record.fileExtension)"
    let destinationURL = URL.documentsDirectory.appendingPathComponent(fileName)

    // Create AsyncStream for delegate events
    // Pass destinationURL to delegate so it can move file immediately in callback
    var downloadDelegate: DownloadSessionDelegate?
    let eventStream = AsyncStream<DownloadSessionDelegate.DownloadEvent> { continuation in
      downloadDelegate = DownloadSessionDelegate(
        continuation: continuation,
        destinationURL: destinationURL
      )
    }

    // Create URLSession with delegate
    let session = URLSession(
      configuration: .default,
      delegate: downloadDelegate,
      delegateQueue: nil  // Use system queue for callbacks
    )

    // Start download task
    let downloadTask = session.downloadTask(with: url)
    urlSessionTasks[record.id] = downloadTask
    downloadTask.resume()

    // Track for progress throttling
    var lastProgressUpdate = Date()
    var finalURL: URL?

    // Process events from delegate
    for await event in eventStream {
      // Check for cancellation or expiration
      try Task.checkCancellation()
      if checkExpired() {
        downloadTask.cancel()
        throw DownloadError.taskExpired
      }

      switch event {
      case .progress(let update):
        // Update total bytes if known
        if update.totalBytesExpectedToWrite > 0 {
          record.totalBytes = update.totalBytesExpectedToWrite
        }

        // Throttle progress updates to avoid excessive main thread work
        let now = Date()
        if now.timeIntervalSince(lastProgressUpdate) >= 0.3 {
          lastProgressUpdate = now

          let fraction = update.fractionCompleted

          // Update Live Activity progress (if BGTask)
          if let bgTask {
            bgTask.progress.completedUnitCount = Int64(fraction * 100)
            bgTask.updateTitle("Downloading video", subtitle: "\(Int(fraction * 100))%")
          }

          // Update record
          record.downloadedBytes = update.totalBytesWritten
          try? context.save()

          // Update observable state on main thread
          updateProgress(recordID: record.id, fraction: fraction, state: .downloading)
        }

      case .completed(let movedURL):
        // File was already moved to destination in delegate callback
        finalURL = movedURL

      case .failed(let error):
        urlSessionTasks[record.id] = nil
        session.invalidateAndCancel()
        throw error
      }
    }

    // Clean up
    urlSessionTasks[record.id] = nil
    session.finishTasksAndInvalidate()

    guard let resultURL = finalURL else {
      throw DownloadError.noData
    }

    return resultURL
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

  /// Save resume data to persistent storage.
  private func saveResumeData(recordID: UUID, resumeData: Data?) async {
    guard let modelContainer else { return }

    let context = ModelContext(modelContainer)
    let descriptor = FetchDescriptor<DownloadRecord>(
      predicate: #Predicate { $0.id == recordID }
    )
    if let record = try? context.fetch(descriptor).first {
      record.resumeData = resumeData
      record.state = .paused
      try? context.save()
    }
  }

  /// Start a download with resume data (for resuming paused downloads).
  private func startDownloadWithResumeData(
    recordID: UUID,
    resumeData: Data,
    bgTask: BGContinuedProcessingTask?,
    checkExpired: @escaping () -> Bool = { false }
  ) {
    let downloadTask = Task { [weak self] in
      guard let self else { return }
      await self.performDownloadWithResumeData(
        recordID: recordID,
        resumeData: resumeData,
        bgTask: bgTask,
        checkExpired: checkExpired
      )
    }
    downloadTasks[recordID] = downloadTask
  }

  /// Perform a download with resume data.
  private func performDownloadWithResumeData(
    recordID: UUID,
    resumeData: Data,
    bgTask: BGContinuedProcessingTask?,
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
    updateProgress(recordID: recordID, fraction: record.fractionCompleted, state: .downloading)

    do {
      // Resume download with resume data
      let destinationURL = try await downloadFileWithResumeData(
        resumeData: resumeData,
        record: record,
        context: context,
        bgTask: bgTask,
        checkExpired: checkExpired
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

  /// Download file using resume data.
  private func downloadFileWithResumeData(
    resumeData: Data,
    record: DownloadRecord,
    context: ModelContext,
    bgTask: BGContinuedProcessingTask?,
    checkExpired: @escaping () -> Bool
  ) async throws -> URL {

    // Prepare destination file path
    let fileName = "\(record.videoID).\(record.fileExtension)"
    let destinationURL = URL.documentsDirectory.appendingPathComponent(fileName)

    // Create AsyncStream for delegate events
    var downloadDelegate: DownloadSessionDelegate?
    let eventStream = AsyncStream<DownloadSessionDelegate.DownloadEvent> { continuation in
      downloadDelegate = DownloadSessionDelegate(
        continuation: continuation,
        destinationURL: destinationURL
      )
    }

    // Create URLSession with delegate
    let session = URLSession(
      configuration: .default,
      delegate: downloadDelegate,
      delegateQueue: nil
    )

    // Start download task with resume data
    let downloadTask = session.downloadTask(withResumeData: resumeData)
    urlSessionTasks[record.id] = downloadTask
    downloadTask.resume()

    // Track for progress throttling
    var lastProgressUpdate = Date()
    var finalURL: URL?

    // Process events from delegate
    for await event in eventStream {
      try Task.checkCancellation()
      if checkExpired() {
        downloadTask.cancel()
        throw DownloadError.taskExpired
      }

      switch event {
      case .progress(let update):
        if update.totalBytesExpectedToWrite > 0 {
          record.totalBytes = update.totalBytesExpectedToWrite
        }

        let now = Date()
        if now.timeIntervalSince(lastProgressUpdate) >= 0.3 {
          lastProgressUpdate = now

          let fraction = update.fractionCompleted

          if let bgTask {
            bgTask.progress.completedUnitCount = Int64(fraction * 100)
            bgTask.updateTitle("Downloading video", subtitle: "\(Int(fraction * 100))%")
          }

          record.downloadedBytes = update.totalBytesWritten
          try? context.save()

          updateProgress(recordID: record.id, fraction: fraction, state: .downloading)
        }

      case .completed(let movedURL):
        finalURL = movedURL

      case .failed(let error):
        urlSessionTasks[record.id] = nil
        session.invalidateAndCancel()
        throw error
      }
    }

    urlSessionTasks[record.id] = nil
    session.finishTasksAndInvalidate()

    guard let resultURL = finalURL else {
      throw DownloadError.noData
    }

    return resultURL
  }
}
