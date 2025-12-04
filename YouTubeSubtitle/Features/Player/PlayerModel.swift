//
//  PlayerModel.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/04.
//

import Foundation

/// Observable model for PlayerView that holds frequently updated playback state.
/// This separates mutable playback state from the view to improve performance
/// and enable better state management.
@Observable
final class PlayerModel {

  // MARK: - Playback State (updated every 500ms)

  /// Current playback position in seconds
  var currentTime: Double = 0

  /// Whether the video is currently playing
  var isPlaying: Bool = false

  // MARK: - Video Info

  /// Total duration of the video in seconds
  var duration: Double = 0

  // MARK: - Playback Rate

  /// Current playback speed (1.0 = normal)
  var playbackRate: Double = 1.0

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
  var isLoopingEnabled: Bool = false

  // MARK: - Computed Properties

  /// The time to display (drag time when dragging, otherwise current time)
  var displayTime: Double {
    isDraggingSlider ? dragTime : currentTime
  }

  /// Whether A-B repeat can be toggled (both points are set)
  var canToggleRepeat: Bool {
    repeatStartTime != nil && repeatEndTime != nil
  }

  // MARK: - Methods

  /// Sets the A point for repeat to current time
  func setRepeatStartToCurrent() {
    repeatStartTime = currentTime
    if repeatEndTime == nil {
      isRepeating = false
    } else if let end = repeatEndTime, currentTime < end {
      isRepeating = true
    }
  }

  /// Sets the B point for repeat to current time
  func setRepeatEndToCurrent() {
    repeatEndTime = currentTime
    if repeatStartTime == nil {
      isRepeating = false
    } else if let start = repeatStartTime, currentTime > start {
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
          currentTime >= endTime else {
      return nil
    }
    return startTime
  }

  /// Checks if video has ended and should loop back to the beginning
  /// Returns 0 if should loop, nil otherwise
  func checkEndOfVideoLoop() -> Double? {
    guard isLoopingEnabled,
          duration > 0,
          currentTime >= duration - 0.5 else {
      return nil
    }
    return 0
  }

  /// Toggles loop playback
  func toggleLoop() {
    isLoopingEnabled.toggle()
  }
}
