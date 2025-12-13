//
//  PlayerModel.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/04.
//

import Foundation
import SwiftUI

// MARK: - CurrentTime

/// Observable wrapper for current playback time.
/// By wrapping the time value in an @Observable class, only views that actually
/// read `.value` will re-render when the time updates (every ~100ms).
/// Intermediate views that just pass the reference won't re-render.
@Observable
final class CurrentTime: @unchecked Sendable {
  var value: Double = 0
}

// MARK: - PlayerModel

/// Observable model for PlayerView that holds frequently updated playback state
/// and manages the PlayerController.
/// This separates mutable playback state and control logic from the view to improve
/// performance and enable better state management.
@Observable
@MainActor
final class PlayerModel {

  // MARK: - Playback State (updated every 500ms)

  /// Current playback position in seconds.
  /// Wrapped in @Observable class to prevent intermediate view re-renders.
  let currentTime = CurrentTime()

  /// Whether the video is currently playing
  var isPlaying: Bool = false

  // MARK: - Video Info

  /// Total duration of the video in seconds
  var duration: Double = 0

  // MARK: - Playback Rate

  /// Current playback speed (1.0 = normal)
  var playbackRate: Double = 1.0

  // MARK: - Seek Intervals

  /// Backward seek interval in seconds
  @ObservationIgnored
  @AppStorage("backwardSeekInterval") var backwardSeekInterval: Double = 3

  /// Forward seek interval in seconds
  @ObservationIgnored
  @AppStorage("forwardSeekInterval") var forwardSeekInterval: Double = 3

  // MARK: - Slider/Seeking State

  /// Whether the user is currently dragging the slider
  var isDraggingSlider: Bool = false

  /// The time position while dragging
  var dragTime: Double = 0

  // MARK: - Repeat (A-B Loop) State

  /// Start time for A-B repeat
  var repeatStartTime: Double?

  /// End time for A-B repeat
  var repeatEndTime: Double?

  /// Whether A-B repeat is active
  var isRepeating: Bool = false

  // MARK: - Full Video Loop State

  /// Whether the video should loop when it reaches the end
  var isLoopingEnabled: Bool = true

  // MARK: - Subtitle State

  /// Current subtitle cues for subtitle-based seeking
  var cues: [Subtitle.Cue] = []

  // MARK: - Controller State

  /// The player controller (YouTube or local)
  private(set) var controller: PlayerController?

  /// Task for tracking playback time
  private var trackingTask: Task<Void, Never>?

  /// Current playback source
  private(set) var playbackSource: PlaybackSource = .youtube

  /// Local video file URL (when downloaded)
  var localFileURL: URL?

  /// Whether the controller is ready
  var isControllerReady: Bool {
    controller != nil
  }

  // MARK: - Computed Properties

  /// The time to display (drag time when dragging, otherwise current time)
  var displayTime: Double {
    isDraggingSlider ? dragTime : currentTime.value
  }

  /// Whether A-B repeat can be toggled (both points are set)
  var canToggleRepeat: Bool {
    repeatStartTime != nil && repeatEndTime != nil
  }

  // MARK: - Methods

  /// Sets the A point for repeat to current time
  func setRepeatStartToCurrent() {
    repeatStartTime = currentTime.value
    if repeatEndTime == nil {
      isRepeating = false
    } else if let end = repeatEndTime, currentTime.value < end {
      isRepeating = true
    }
  }

  /// Sets the B point for repeat to current time
  func setRepeatEndToCurrent() {
    repeatEndTime = currentTime.value
    if repeatStartTime == nil {
      isRepeating = false
    } else if let start = repeatStartTime, currentTime.value > start {
      isRepeating = true
    }
  }

  /// Clears all repeat state
  func clearRepeat() {
    repeatStartTime = nil
    repeatEndTime = nil
    isRepeating = false
  }

  /// Toggles repeat if both A and B points are set
  func toggleRepeat() {
    guard canToggleRepeat else { return }
    isRepeating.toggle()
  }

  /// Checks if current time has passed the repeat end point and returns the start time if so
  func checkRepeatLoop() -> Double? {
    guard isRepeating,
          let startTime = repeatStartTime,
          let endTime = repeatEndTime,
          currentTime.value >= endTime else {
      return nil
    }
    return startTime
  }

  /// Checks if video has ended and should loop back to the beginning
  /// Returns 0 if should loop, nil otherwise
  func checkEndOfVideoLoop() -> Double? {
    guard isLoopingEnabled,
          duration > 0,
          currentTime.value >= duration - 0.5 else {
      return nil
    }
    return 0
  }

  /// Toggles loop playback
  func toggleLoop() {
    isLoopingEnabled.toggle()
  }

  // MARK: - Subtitle-based Seeking

  /// Returns the start time of the previous subtitle cue relative to current time.
  /// - Returns: Start time of the previous cue, or nil if at the beginning
  func previousSubtitleTime() -> Double? {
    guard !cues.isEmpty else { return nil }

    // Find the last cue that starts before current time (with small threshold)
    let threshold = 0.5 // If we're less than 0.5s into current cue, go to previous one
    let adjustedTime = currentTime.value - threshold

    // Find all cues before adjusted time
    let previousCues = cues.filter { $0.startTime < adjustedTime }

    // Return the last one (most recent)
    return previousCues.last?.startTime
  }

  /// Returns the start time of the next subtitle cue relative to current time.
  /// - Returns: Start time of the next cue, or nil if at the end
  func nextSubtitleTime() -> Double? {
    guard !cues.isEmpty else { return nil }

    // Find the first cue that starts after current time
    return cues.first(where: { $0.startTime > currentTime.value })?.startTime
  }

  /// Returns the start time of the current subtitle cue.
  /// - Returns: Start time of the current cue, or nil if no matching cue
  func currentSubtitleTime() -> Double? {
    guard !cues.isEmpty else { return nil }

    // Find the cue that contains current time
    return cues.first(where: {
      $0.startTime <= currentTime.value && currentTime.value < $0.endTime
    })?.startTime
  }

  // MARK: - Controller Lifecycle

  /// Loads the video and initializes the appropriate controller
  func loadVideo(videoItem: VideoItem) {
    // Prevent multiple loads
    guard controller == nil else { return }

    // Check if video is downloaded
    if videoItem.isDownloaded,
       let fileURL = videoItem.downloadedFileURL {
      // Store local file URL for later switching
      localFileURL = fileURL
      // Use local file playback by default when available
      controller = .local(LocalVideoPlayerController(url: fileURL))
      playbackSource = .local
    } else {
      // Use YouTube playback
      controller = .youtube(YouTubeVideoPlayerController(videoID: videoItem.videoID.rawValue))
      playbackSource = .youtube
    }

    startTrackingTime()
  }

  /// Cleans up resources when the view disappears
  func cleanup() {
    trackingTask?.cancel()
    trackingTask = nil

    if let controller {
      Task {
        await controller.pause()
      }
    }
  }

  // MARK: - Playback Control

  /// Seeks to the specified time
  func seek(to time: Double) {
    guard let controller else { return }
    Task {
      await controller.seek(to: time)
    }
  }

  /// Seeks backward by the default backward interval
  func seekBackward() {
    seekBackward(interval: backwardSeekInterval)
  }

  /// Seeks backward by the specified interval
  func seekBackward(interval: Double) {
    guard let controller else { return }
    Task {
      let currentSeconds = await controller.currentTime
      let newSeconds = max(0, currentSeconds - interval)
      await controller.seek(to: newSeconds)
    }
  }

  /// Seeks forward by the default forward interval
  func seekForward() {
    seekForward(interval: forwardSeekInterval)
  }

  /// Seeks forward by the specified interval
  func seekForward(interval: Double) {
    guard let controller else { return }
    Task {
      let currentSeconds = await controller.currentTime
      let newSeconds = currentSeconds + interval
      await controller.seek(to: newSeconds)
    }
  }

  /// Seeks to the previous subtitle
  func seekToPreviousSubtitle() {
    guard let controller else { return }
    Task {
      if let previousTime = previousSubtitleTime() {
        await controller.seek(to: previousTime)
      }
    }
  }

  /// Seeks to the next subtitle
  func seekToNextSubtitle() {
    guard let controller else { return }
    Task {
      if let nextTime = nextSubtitleTime() {
        await controller.seek(to: nextTime)
      }
    }
  }

  /// Toggles play/pause
  func togglePlayPause() {
    guard let controller else { return }
    Task {
      if controller.isPlaying {
        await controller.pause()
        isPlaying = false
      } else {
        await controller.play()
        isPlaying = true
      }
    }
  }

  /// Sets the playback rate
  func setPlaybackRate(_ rate: Double) {
    guard let controller else { return }
    Task {
      await controller.setPlaybackRate(rate)
      playbackRate = rate
    }
  }

  // MARK: - Source Switching

  /// Switches playback source between YouTube and local
  func switchPlaybackSource(to source: PlaybackSource) {
    guard source != playbackSource else { return }

    // Cancel existing tracking task
    trackingTask?.cancel()

    // Stop current player before switching
    if let currentController = controller {
      Task {
        await currentController.pause()
      }
    }

    // Create new controller based on source
    switch source {
    case .youtube:
      // Need videoID for this - caller should ensure this is valid
      // For now, we'll log an error if localFileURL is used to infer videoID
      break
    case .local:
      guard let fileURL = localFileURL else { return }
      controller = .local(LocalVideoPlayerController(url: fileURL))
    }

    playbackSource = source

    // Start new time tracking
    startTrackingTime()
  }

  /// Switches to YouTube playback with the given video ID
  func switchToYouTube(videoID: String) {
    guard playbackSource != .youtube else { return }

    trackingTask?.cancel()

    if let currentController = controller {
      Task {
        await currentController.pause()
      }
    }

    controller = .youtube(YouTubeVideoPlayerController(videoID: videoID))
    playbackSource = .youtube
    startTrackingTime()
  }

  /// Switches to local playback
  func switchToLocal() {
    guard playbackSource != .local, let fileURL = localFileURL else { return }

    trackingTask?.cancel()

    if let currentController = controller {
      Task {
        await currentController.pause()
      }
    }

    controller = .local(LocalVideoPlayerController(url: fileURL))
    playbackSource = .local
    startTrackingTime()
  }

  // MARK: - Scene Phase Handling

  /// Handles scene phase changes (background/foreground)
  func handleScenePhaseChange(to newPhase: ScenePhase) {
    guard let controller else { return }

    // When entering background, pause all playback
    // (Background audio mode has been removed to comply with App Store guidelines)
    if newPhase == .background {
      Task {
        await controller.pause()
        isPlaying = false
      }
    }
  }

  // MARK: - Private Methods

  private func startTrackingTime() {
    // Cancel any existing tracking task
    trackingTask?.cancel()

    trackingTask = Task { [weak self] in
      guard let self else { return }

//      // Initial delay to get duration
//      try? await Task.sleep(for: .seconds(1))

      guard !Task.isCancelled else { return }

      if let controller = self.controller {
        let videoDuration = await controller.duration
        self.duration = videoDuration
      }

      // Main tracking loop
      while !Task.isCancelled {
        if let controller = self.controller {
          let timeValue = await controller.currentTime
          self.currentTime.value = timeValue
          self.isPlaying = controller.isPlaying
        }

        // Check A-B repeat loop
        if let loopStartTime = self.checkRepeatLoop() {
          await self.controller?.seek(to: loopStartTime)
        }
        // Check end-of-video loop
        else if let loopStartTime = self.checkEndOfVideoLoop() {
          await self.controller?.seek(to: loopStartTime)
        }

        try? await Task.sleep(for: .milliseconds(100))
      }
    }
  }
}
