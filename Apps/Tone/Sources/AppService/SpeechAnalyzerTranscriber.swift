import AVFoundation
import Foundation
import Speech

public enum SpeechAnalyzerTranscriber {

  public enum Error: LocalizedError {
    case notAvailable
    case unsupportedLocale(Locale)
    case assetInstallationFailed(any Swift.Error)
    case audioFileCreationFailed(any Swift.Error)
    case transcriptionFailed(any Swift.Error)
    case failedToTranscribe

    public var errorDescription: String? {
      switch self {
      case .notAvailable:
        return "Speech transcription is not available on this device."
      case .unsupportedLocale(let locale):
        return "Language '\(locale.identifier)' is not supported for transcription."
      case .assetInstallationFailed(let error):
        return "Failed to prepare speech recognition assets: \(error.localizedDescription)"
      case .audioFileCreationFailed(let error):
        return "Failed to read audio file: \(error.localizedDescription)"
      case .transcriptionFailed(let error):
        return "Transcription failed: \(error.localizedDescription)"
      case .failedToTranscribe:
        return "No speech detected in the audio."
      }
    }
  }

  public struct Result: Sendable {
    let audioFileURL: URL
    let segments: [AbstractSegment]
  }

  @MainActor
  public static func run(
    url input: URL,
    locale: Locale = Locale(identifier: "en-US"),
    progressHandler: (@Sendable (Double) -> Void)? = nil,
    shouldContinue: (@Sendable () -> Bool)? = nil
  ) async throws -> Result {

    let hasSecurityScope = input.startAccessingSecurityScopedResource()

    defer {
      if hasSecurityScope {
        input.stopAccessingSecurityScopedResource()
      }
    }

    guard SpeechTranscriber.isAvailable else {
      throw Error.notAvailable
    }

    guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      throw Error.unsupportedLocale(locale)
    }

    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )

    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
    } catch {
      throw Error.assetInstallationFailed(error)
    }

    let audioFile: AVAudioFile
    do {
      audioFile = try AVAudioFile(forReading: input)
    } catch {
      throw Error.audioFileCreationFailed(error)
    }

    let totalFrames = Double(audioFile.length)
    let sampleRate = audioFile.processingFormat.sampleRate
    let totalDuration = totalFrames / sampleRate

    let analyzer = SpeechAnalyzer(modules: [transcriber])

    let resultsTask = Task { @MainActor in
      var segments: [AbstractSegment] = []

      do {
        for try await result in transcriber.results {
          try Task.checkCancellation()

          if let shouldContinue, !shouldContinue() {
            throw CancellationError()
          }

          let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
          var resultSegments: [AbstractSegment] = []
          var startSeconds: Double?
          var endSeconds: Double?

          for run in result.text.runs {
            guard let timeRange = run.audioTimeRange else { continue }

            let runStart = timeRange.start.seconds
            let runEnd = timeRange.end.seconds
            let wordText = String(result.text[run.range].characters)
              .trimmingCharacters(in: .whitespacesAndNewlines)

            if startSeconds == nil || runStart < startSeconds! {
              startSeconds = runStart
            }
            if endSeconds == nil || runEnd > endSeconds! {
              endSeconds = runEnd
            }

            guard !wordText.isEmpty else { continue }

            resultSegments.append(
              AbstractSegment(
                startTime: TimeInterval(runStart),
                endTime: TimeInterval(runEnd),
                text: wordText
              )
            )
          }

          if resultSegments.isEmpty, !text.isEmpty {
            resultSegments.append(
              AbstractSegment(
                startTime: TimeInterval(startSeconds ?? 0),
                endTime: TimeInterval(endSeconds ?? 0),
                text: text
              )
            )
          }

          segments.append(contentsOf: resultSegments)

          if totalDuration > 0, let endSeconds {
            progressHandler?(min(endSeconds / totalDuration, 1.0))
          }
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw Error.transcriptionFailed(error)
      }

      return segments
    }

    do {
      let lastTime = try await analyzer.analyzeSequence(from: audioFile)
      if let lastTime {
        try await analyzer.finalizeAndFinish(through: lastTime)
      }
    } catch {
      resultsTask.cancel()
      throw Error.transcriptionFailed(error)
    }

    let segments = try await resultsTask.value

    guard !segments.isEmpty else {
      throw Error.failedToTranscribe
    }

    progressHandler?(1)

    return Result(audioFileURL: input, segments: segments)
  }
}
