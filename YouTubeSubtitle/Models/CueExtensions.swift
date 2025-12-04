//
//  CueExtensions.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/01.
//

import Foundation
import SwiftSubtitles
import YoutubeTranscript

// MARK: - Subtitles.Cue Extensions

extension Subtitles.Cue {
  /// Start time in seconds
  var startTimeSeconds: Double {
    startTime.totalSeconds
  }

  /// End time in seconds
  var endTimeSeconds: Double {
    endTime.totalSeconds
  }

  /// SRT formatted timestamp string (HH:MM:SS,mmm --> HH:MM:SS,mmm)
  var srtTimestamp: String {
    "\(formatSRTTime(startTimeSeconds)) --> \(formatSRTTime(endTimeSeconds))"
  }

  /// SRT formatted entry string
  var srtFormat: String {
    """
    \(id)
    \(srtTimestamp)
    \(text)
    """
  }

  private func formatSRTTime(_ seconds: Double) -> String {
    let totalMilliseconds = Int(seconds * 1000)
    let hours = totalMilliseconds / 3600000
    let minutes = (totalMilliseconds % 3600000) / 60000
    let secs = (totalMilliseconds % 60000) / 1000
    let millis = totalMilliseconds % 1000

    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
  }
}

// MARK: - Subtitles.Time Extension

extension Subtitles.Time {
  /// Total time in seconds
  var totalSeconds: Double {
    Double(hour * 3600 + minute * 60 + second) + Double(millisecond) / 1000.0
  }

  /// Initialize from total seconds
  init(timeInSeconds: Double) {
    let totalMilliseconds = Int(timeInSeconds * 1000)
    let hours = totalMilliseconds / 3600000
    let minutes = (totalMilliseconds % 3600000) / 60000
    let seconds = (totalMilliseconds % 60000) / 1000
    let millis = totalMilliseconds % 1000

    self.init(hour: UInt(hours), minute: UInt(minutes), second: UInt(seconds), millisecond: UInt(millis))
  }
}

// MARK: - TranscriptResponse Extensions

extension Array where Element == TranscriptResponse {
  /// Convert TranscriptResponse array to SwiftSubtitles format
  func toSwiftSubtitles() -> Subtitles {
    SubtitleAdapter.toSwiftSubtitles(self)
  }
}
