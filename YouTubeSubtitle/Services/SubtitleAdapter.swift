//
//  SubtitleAdapter.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/01.
//

import Foundation
import SwiftSubtitles
import YoutubeTranscript

/// Adapter for converting between YouTube transcripts and SwiftSubtitles format
struct SubtitleAdapter {

  // MARK: - YouTube Transcript -> SwiftSubtitles Conversion

  /// Convert YouTube TranscriptResponse array to SwiftSubtitles format
  static func toSwiftSubtitles(_ transcripts: [TranscriptResponse]) -> Subtitles {
    let cues = transcripts.enumerated().map { index, transcript in
      Subtitles.Cue(
        position: index + 1,
        startTime: Subtitles.Time(timeInSeconds: transcript.offset),
        endTime: Subtitles.Time(timeInSeconds: transcript.offset + transcript.duration),
        text: transcript.text
      )
    }
    return Subtitles(cues)
  }

  // MARK: - File Format Encoding/Decoding

  /// Encode subtitles to specified format (srt, vtt, sbv, etc.)
  static func encode(_ subtitles: Subtitles, format: SubtitleFormat) throws -> String {
    try Subtitles.encode(subtitles, fileExtension: format.fileExtension)
  }

  /// Decode subtitles from data with specified format
  static func decode(data: Data, format: SubtitleFormat) throws -> Subtitles {
    guard let content = String(data: data, encoding: .utf8) else {
      throw SubtitleError.invalidEncoding
    }

    return try Subtitles(content: content, expectedExtension: format.fileExtension)
  }

  /// Decode subtitles from file URL (auto-detects format from extension)
  static func decode(from url: URL) throws -> Subtitles {
    try Subtitles(fileURL: url, encoding: .utf8)
  }
}

// MARK: - Subtitle Format Enum

enum SubtitleFormat: String, CaseIterable, Identifiable {
  case srt = "SubRip"
  case vtt = "WebVTT"
  case sbv = "SubViewer"
  case csv = "CSV"
  case lrc = "Lyrics"
  case ttml = "TTML"

  var id: String { rawValue }

  var fileExtension: String {
    switch self {
    case .srt: return "srt"
    case .vtt: return "vtt"
    case .sbv: return "sbv"
    case .csv: return "csv"
    case .lrc: return "lrc"
    case .ttml: return "ttml"
    }
  }
}

// MARK: - Errors

enum SubtitleError: LocalizedError {
  case invalidEncoding
  case unsupportedFormat
  case decodingFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidEncoding:
      return "Failed to decode subtitle file with UTF-8 encoding"
    case .unsupportedFormat:
      return "Unsupported subtitle format"
    case .decodingFailed(let message):
      return "Failed to decode subtitle: \(message)"
    }
  }
}

