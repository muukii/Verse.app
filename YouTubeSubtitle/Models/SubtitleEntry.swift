//
//  SubtitleEntry.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/01.
//

import Foundation
import SwiftSubtitles
import YoutubeTranscript

/// Subtitle entry compatible with SRT format and SwiftSubtitles
struct SubtitleEntry: Identifiable, Equatable, Sendable {
  let id: Int              // Sequence number (starting from 1)
  let startTime: Double    // Start time (seconds)
  let endTime: Double      // End time (seconds)
  let text: String         // Subtitle text

  /// Initialize from TranscriptResponse
  init(id: Int, transcript: TranscriptResponse) {
    self.id = id
    self.startTime = transcript.offset
    self.endTime = transcript.offset + transcript.duration
    self.text = transcript.text
  }

  /// Initialize from SwiftSubtitles Cue
  init(cue: Subtitles.Cue) {
    self.id = cue.position ?? 0
    self.startTime = cue.startTime.totalSeconds
    self.endTime = cue.endTime.totalSeconds
    self.text = cue.text
  }

  /// Direct initialization
  init(id: Int, startTime: Double, endTime: Double, text: String) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.text = text
  }

  /// Convert to SwiftSubtitles Cue
  func toCue() -> Subtitles.Cue {
    Subtitles.Cue(
      position: id,
      startTime: Subtitles.Time(timeInSeconds: startTime),
      endTime: Subtitles.Time(timeInSeconds: endTime),
      text: text
    )
  }
}

extension SubtitleEntry {
  /// SRT形式のタイムスタンプ文字列を生成（HH:MM:SS,mmm）
  var srtTimestamp: String {
    "\(formatSRTTime(startTime)) --> \(formatSRTTime(endTime))"
  }
  
  /// SRT形式の文字列を生成
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

extension Array where Element == TranscriptResponse {
  /// Convert TranscriptResponse array to SubtitleEntry array
  func toSubtitleEntries() -> [SubtitleEntry] {
    enumerated().map { index, transcript in
      SubtitleEntry(id: index + 1, transcript: transcript)
    }
  }

  /// Convert TranscriptResponse array to SwiftSubtitles format
  func toSwiftSubtitles() -> Subtitles {
    SubtitleAdapter.toSwiftSubtitles(self)
  }
}

extension Array where Element == SubtitleEntry {
  /// Convert SubtitleEntry array to SwiftSubtitles format
  func toSwiftSubtitles() -> Subtitles {
    let cues = map { $0.toCue() }
    return Subtitles(cues)
  }
}

extension Subtitles {
  /// Convert SwiftSubtitles to SubtitleEntry array
  func toSubtitleEntries() -> [SubtitleEntry] {
    cues.map { SubtitleEntry(cue: $0) }
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
