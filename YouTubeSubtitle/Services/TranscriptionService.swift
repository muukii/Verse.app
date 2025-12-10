//
//  TranscriptionService.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/05.
//

import AVFoundation
import Speech
import SwiftSubtitles

/// Service for transcribing audio from video files using Apple's SpeechAnalyzer API (iOS 26+).
@MainActor
final class TranscriptionService {
  static let shared = TranscriptionService()

  private init() {}

  // MARK: - Types

  enum TranscriptionError: LocalizedError {
    case notAvailable
    case unsupportedLocale(Locale)
    case assetInstallationFailed(any Error)
    case audioFileCreationFailed(any Error)
    case transcriptionFailed(any Error)
    case noResults

    var errorDescription: String? {
      switch self {
      case .notAvailable:
        return "Speech transcription is not available on this device. Please use a physical device with iOS 26 or later."
      case .unsupportedLocale(let locale):
        return "Language '\(locale.identifier)' is not supported for transcription"
      case .assetInstallationFailed(let error):
        return "Failed to download speech recognition model: \(error.localizedDescription)"
      case .audioFileCreationFailed(let error):
        return "Failed to read audio file: \(error.localizedDescription)"
      case .transcriptionFailed(let error):
        return "Transcription failed: \(error.localizedDescription)"
      case .noResults:
        return "No speech detected in the audio"
      }
    }
  }

  /// Result containing both plain subtitles and rich attributed texts with word-level timing
  struct TranscriptionResult {
    let subtitles: Subtitles
    /// Attributed texts with audioTimeRange attributes for word-level highlighting.
    /// Array indices correspond to cue positions (0-indexed).
    let attributedTexts: [AttributedString]
  }

  enum TranscriptionState: Equatable {
    case idle
    case preparingAssets
    case transcribing(progress: Double)
    case completed
    case failed(String)

    static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
      switch (lhs, rhs) {
      case (.idle, .idle): return true
      case (.preparingAssets, .preparingAssets): return true
      case (.transcribing(let p1), .transcribing(let p2)): return p1 == p2
      case (.completed, .completed): return true
      case (.failed(let m1), .failed(let m2)): return m1 == m2
      default: return false
      }
    }
  }

  // MARK: - Public Methods

  /// Transcribes audio from a video file to subtitles.
  /// - Parameters:
  ///   - fileURL: URL to the video file (MP4)
  ///   - locale: Language locale for transcription (defaults to device locale)
  ///   - onStateChange: Callback for state updates during transcription
  /// - Returns: TranscriptionResult containing subtitles and attributed texts with word-level timing
  func transcribe(
    fileURL: URL,
    locale: Locale = .current,
    onStateChange: @escaping @MainActor (TranscriptionState) -> Void
  ) async throws -> TranscriptionResult {
    // 0. Check device availability (not available on Simulator)
    guard SpeechTranscriber.isAvailable else {
      throw TranscriptionError.notAvailable
    }

    // 1. Check supported locale
    guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      throw TranscriptionError.unsupportedLocale(locale)
    }

    // 2. Create transcriber with explicit options to include timing information
    // Must specify attributeOptions: [.audioTimeRange] to get timing data in results
    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )

    // 3. Install assets if needed (offline model download)
    onStateChange(.preparingAssets)
    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
    } catch {
      throw TranscriptionError.assetInstallationFailed(error)
    }

    // 4. Create AVAudioFile from video
    let audioFile: AVAudioFile
    do {
      audioFile = try AVAudioFile(forReading: fileURL)
    } catch {
      throw TranscriptionError.audioFileCreationFailed(error)
    }

    // 5. Calculate total duration for progress reporting
    let totalFrames = Double(audioFile.length)
    let sampleRate = audioFile.processingFormat.sampleRate
    let totalDuration = totalFrames / sampleRate

    // 6. Run transcription
    onStateChange(.transcribing(progress: 0))

    let analyzer = SpeechAnalyzer(modules: [transcriber])
    var cues: [Subtitles.Cue] = []
    var attributedTexts: [AttributedString] = []
    var position = 0

    // Task to collect results
    let resultsTask = Task { @MainActor in
      do {
        for try await result in transcriber.results {
          position += 1

          let text = String(result.text.characters)
          // Preserve the original AttributedString with audioTimeRange attributes
          let attributedText = result.text
          attributedTexts.append(attributedText)

          // Extract time range from AttributedString runs
          // We need to find the earliest start time and latest end time across all runs
          var startSeconds: Double?
          var endSeconds: Double?

          for run in result.text.runs {
            if let timeRange = run.audioTimeRange {
              let runStart = timeRange.start.seconds
              let runEnd = timeRange.end.seconds

              if startSeconds == nil || runStart < startSeconds! {
                startSeconds = runStart
              }
              if endSeconds == nil || runEnd > endSeconds! {
                endSeconds = runEnd
              }
            }
          }

          // Use 0 as fallback if no timing info available
          let finalStartSeconds = startSeconds ?? 0
          let finalEndSeconds = endSeconds ?? 0

          let cue = Subtitles.Cue(
            position: position,
            startTime: Subtitles.Time(timeInSeconds: finalStartSeconds),
            endTime: Subtitles.Time(timeInSeconds: finalEndSeconds),
            text: text
          )
          cues.append(cue)

          // Update progress based on end time
          if totalDuration > 0 && finalEndSeconds > 0 {
            let progress = min(finalEndSeconds / totalDuration, 1.0)
            onStateChange(.transcribing(progress: progress))
          }
        }
      } catch {
        throw TranscriptionError.transcriptionFailed(error)
      }
    }

    // Run analysis
    do {
      let lastTime = try await analyzer.analyzeSequence(from: audioFile)
      if let lastTime {
        try await analyzer.finalizeAndFinish(through: lastTime)
      }
    } catch {
      resultsTask.cancel()
      throw TranscriptionError.transcriptionFailed(error)
    }

    // Wait for results collection to complete
    try await resultsTask.value

    // 7. Validate results
    if cues.isEmpty {
      throw TranscriptionError.noResults
    }

    onStateChange(.completed)
    return TranscriptionResult(
      subtitles: Subtitles(cues),
      attributedTexts: attributedTexts
    )
  }
}
