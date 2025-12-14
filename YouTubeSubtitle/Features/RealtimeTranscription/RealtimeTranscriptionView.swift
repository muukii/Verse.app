//
//  RealtimeTranscriptionView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/09.
//

@preconcurrency import AVFoundation
import CoreMedia
import Speech
import SwiftUI
import Translation

/// Sample view demonstrating real-time microphone transcription using SpeechAnalyzer (iOS 26+)
struct RealtimeTranscriptionView: View {
  @State private var viewModel = RealtimeTranscriptionViewModel()
  @State private var selectedWord: String?
  @State private var showWordDetail = false
  @State private var explainText: String?
  @State private var showExplainSheet = false

  var body: some View {
    VStack(spacing: 0) {
      // Header
      headerSection

      // Transcription output
      transcriptionSection

      // Controls
      controlsSection
    }
    .navigationTitle("Live Transcription")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      await viewModel.prepareIfNeeded()
    }
    .onDisappear {
      // Stop recording when view disappears
      if viewModel.isRecording {
        Task {
          await viewModel.stopRecording()
        }
      }
      // Re-enable idle timer when leaving the view
      UIApplication.shared.isIdleTimerDisabled = false
    }
    .onChange(of: viewModel.isRecording) { _, isRecording in
      // Prevent screen sleep during recording
      UIApplication.shared.isIdleTimerDisabled = isRecording
    }
    .sheet(isPresented: $showWordDetail) {
      if let word = selectedWord {
        WordDetailSheet(word: word)
      }
    }
    .sheet(isPresented: $showExplainSheet) {
      if let text = explainText {
        ExplainSheet(text: text)
      }
    }
  }

  // MARK: - Header Section

  private var headerSection: some View {
    VStack(spacing: 8) {
      // Status indicator
      HStack(spacing: 8) {
        Circle()
          .fill(statusColor)
          .frame(width: 12, height: 12)

        Text(viewModel.status.displayText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 8)

      // Audio level meter
      if viewModel.isRecording {
        AudioLevelMeter(level: viewModel.audioLevel)
          .frame(height: 4)
          .padding(.horizontal, 40)
      }
    }
    .padding()
    .background(Color(.secondarySystemBackground))
  }

  private var statusColor: Color {
    switch viewModel.status {
    case .idle:
      return .gray
    case .preparing:
      return .orange
    case .ready:
      return .green
    case .recording:
      return .red
    case .error:
      return .red
    }
  }

  // MARK: - Transcription Section

  private var transcriptionSection: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(viewModel.transcriptions) { item in
            TranscriptionBubble(
              item: item,
              onWordTap: { word in
                selectedWord = word
                showWordDetail = true
              },
              onExplain: { text in
                explainText = text
                showExplainSheet = true
              }
            )
            .id(item.id)
          }

          // Current partial transcription
          if let partial = viewModel.partialTranscription, !partial.isEmpty {
            Text(partial)
              .font(.body)
              .foregroundStyle(.secondary)
              .italic()
              .padding(.horizontal, 16)
              .id("partial")
          }
        }
        .padding()
      }
      .onChange(of: viewModel.transcriptions.count) { _, _ in
        withAnimation {
          if let last = viewModel.transcriptions.last {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
      .onChange(of: viewModel.partialTranscription) { _, _ in
        withAnimation {
          proxy.scrollTo("partial", anchor: .bottom)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }

  // MARK: - Controls Section

  private var controlsSection: some View {
    VStack(spacing: 16) {
      Divider()

      HStack(spacing: 24) {
        // Clear button
        Button {
          viewModel.clearTranscriptions()
        } label: {
          Label("Clear", systemImage: "trash")
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.transcriptions.isEmpty)

        // Share button
        ShareLink(item: viewModel.exportText) {
          Label("Share", systemImage: "square.and.arrow.up")
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.transcriptions.isEmpty)

        // Record/Stop button
        Button {
          Task {
            if viewModel.isRecording {
              await viewModel.stopRecording()
            } else {
              await viewModel.startRecording()
            }
          }
        } label: {
          Label(
            viewModel.isRecording ? "Stop" : "Start",
            systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill"
          )
          .font(.headline)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? .red : .blue)
        .disabled(!viewModel.canRecord)
      }
      .padding(.horizontal)
      .padding(.bottom, 16)
    }
    .background(Color(.secondarySystemBackground))
  }
}

// MARK: - Transcription Item

struct TranscriptionItem: Identifiable, Equatable {
  let id = UUID()
  let text: AttributedString
  let timestamp: Date

  var formattedTime: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    return formatter.string(from: timestamp)
  }

  /// Extract word timings from AttributedString's audioTimeRange attributes
  var wordTimings: [Subtitle.WordTiming] {
    var timings: [Subtitle.WordTiming] = []
    var index = text.startIndex
    while index < text.endIndex {
      let run = text.runs[index]
      if let timeRange = run.audioTimeRange {
        let word = String(text[run.range].characters)
        timings.append(Subtitle.WordTiming(
          text: word,
          startTime: timeRange.start.seconds,
          endTime: timeRange.end.seconds
        ))
      }
      index = run.range.upperBound
    }
    return timings
  }

  /// Plain text representation
  var plainText: String {
    String(text.characters)
  }

  static func == (lhs: TranscriptionItem, rhs: TranscriptionItem) -> Bool {
    lhs.id == rhs.id
  }
}

// MARK: - Transcription Bubble

private struct TranscriptionBubble: View {
  let item: TranscriptionItem
  var highlightTime: CMTime?
  var onWordTap: ((String) -> Void)?
  var onExplain: ((String) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      SelectableSubtitleTextView(
        text: item.plainText,
        wordTimings: item.wordTimings,
        highlightTime: highlightTime,
        onWordTap: { word, _ in
          onWordTap?(word)
        },
        onExplain: onExplain
      )
      .fixedSize(horizontal: false, vertical: true)

      Text(item.formattedTime)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(12)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Audio Level Meter

private struct AudioLevelMeter: View {
  let level: Float

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        // Background
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.gray.opacity(0.3))

        // Level indicator
        RoundedRectangle(cornerRadius: 2)
          .fill(levelColor)
          .frame(width: geometry.size.width * CGFloat(normalizedLevel))
          .animation(.linear(duration: 0.1), value: level)
      }
    }
  }

  private var normalizedLevel: Float {
    // Normalize dB level to 0-1 range
    // Typical range: -60dB (silence) to 0dB (max)
    let minDb: Float = -60
    let maxDb: Float = 0
    let clampedLevel = max(minDb, min(maxDb, level))
    return (clampedLevel - minDb) / (maxDb - minDb)
  }

  private var levelColor: Color {
    if normalizedLevel > 0.8 {
      return .red
    } else if normalizedLevel > 0.5 {
      return .yellow
    } else {
      return .green
    }
  }
}

// MARK: - ViewModel

@Observable
@MainActor
final class RealtimeTranscriptionViewModel {

  enum Status {
    case idle
    case preparing
    case ready
    case recording
    case error(String)

    var displayText: String {
      switch self {
      case .idle:
        return "Initializing..."
      case .preparing:
        return "Preparing speech model..."
      case .ready:
        return "Ready to record"
      case .recording:
        return "Recording..."
      case .error(let message):
        return "Error: \(message)"
      }
    }
  }

  // MARK: - Published State

  private(set) var status: Status = .idle
  private(set) var transcriptions: [TranscriptionItem] = []
  private(set) var partialTranscription: String?
  private(set) var audioLevel: Float = -60
  private(set) var isRecording = false

  var canRecord: Bool {
    if case .ready = status { return true }
    if case .recording = status { return true }
    return false
  }

  var exportText: String {
    transcriptions.map { item in
      "[\(item.formattedTime)] \(String(item.text.characters))"
    }.joined(separator: "\n\n")
  }

  // MARK: - Private Properties

  private var audioEngine: AVAudioEngine?
  private var speechAnalyzer: SpeechAnalyzer?
  private var transcriber: SpeechTranscriber?
  private var resultsTask: Task<Void, Never>?
  private var analysisTask: Task<Void, Error>?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

  // MARK: - Public Methods

  func prepareIfNeeded() async {
    guard case .idle = status else { return }

    // Check availability
    guard SpeechTranscriber.isAvailable else {
      status = .error("Not available on Simulator")
      return
    }

    // Get supported locale
    let locale = Locale(identifier: "en_US")
    guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      status = .error("Language not supported")
      return
    }

    // Create transcriber
    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    self.transcriber = transcriber

    // Install assets if needed
    status = .preparing
    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
      }
    } catch {
      status = .error("Model download failed")
      return
    }

    status = .ready
  }

  func startRecording() async {
    guard let transcriber else { return }

    // Request microphone permission
    let authorized = await AVAudioApplication.requestRecordPermission()
    guard authorized else {
      status = .error("Microphone access denied")
      return
    }

    // Configure audio session
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
      try session.setActive(true)
    } catch {
      status = .error("Audio session failed")
      return
    }

    // Setup audio engine
    let engine = AVAudioEngine()
    self.audioEngine = engine

    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    // Create 16-bit PCM format at 16kHz required by SpeechAnalyzer
    // Note: Offline transcription models typically require 16kHz sample rate
    let targetSampleRate: Double = 16000
    guard let pcmFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: targetSampleRate,
      channels: 1,
      interleaved: true
    ) else {
      status = .error("Failed to create audio format")
      return
    }

    // Create audio converter
    guard let converter = AVAudioConverter(from: inputFormat, to: pcmFormat) else {
      status = .error("Failed to create audio converter")
      return
    }

    // Create analyzer
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    self.speechAnalyzer = analyzer

    // Create input stream for analyzer (using AsyncStream.makeStream pattern from docs)
    let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
    self.inputContinuation = inputBuilder

    // Start collecting results
    resultsTask = Task { @MainActor in
      do {
        for try await result in transcriber.results {
          let attributedText = result.text
          if !attributedText.characters.isEmpty {
            let item = TranscriptionItem(text: attributedText, timestamp: Date())
            transcriptions.append(item)
            partialTranscription = nil
          }
        }
      } catch {
        print("Results stream error: \(error)")
      }
    }

    // Start analysis task
    analysisTask = Task {
      do {
        let lastTime = try await analyzer.analyzeSequence(inputSequence)
        if let lastTime {
          try await analyzer.finalizeAndFinish(through: lastTime)
        }
      } catch {
        print("Analysis error: \(error)")
      }
    }

    // Install audio tap to feed buffers to analyzer
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable [weak self] buffer, _ in
      guard let self else { return }

      // Update audio level on main thread
      Task { @MainActor in
        self.updateAudioLevel(buffer: buffer)
      }

      // Convert to 16-bit PCM format required by SpeechAnalyzer
      let frameCount = AVAudioFrameCount(pcmFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate)
      guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
        return
      }

      var error: NSError?
      converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
        outStatus.pointee = .haveData
        return buffer
      }

      if error == nil {
        // Feed converted buffer to analyzer via input stream
        let input = AnalyzerInput(buffer: convertedBuffer)
        self.inputContinuation?.yield(input)
      }
    }

    // Start engine
    do {
      try engine.start()
      isRecording = true
      status = .recording
    } catch {
      status = .error("Audio engine failed")
    }
  }

  func stopRecording() async {
    // Stop engine first
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    audioEngine = nil

    // Finish input stream (this signals end of audio)
    inputContinuation?.finish()
    inputContinuation = nil

    // Wait for analysis to complete
    _ = try? await analysisTask?.value
    analysisTask = nil

    speechAnalyzer = nil

    // Cancel results task
    resultsTask?.cancel()
    resultsTask = nil

    // Deactivate audio session to restore normal audio behavior
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("Failed to deactivate audio session: \(error)")
    }

    isRecording = false
    status = .ready
    audioLevel = -60
  }

  func clearTranscriptions() {
    transcriptions.removeAll()
    partialTranscription = nil
  }

  // MARK: - Private Methods

  private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData?[0] else { return }
    let frameLength = Int(buffer.frameLength)

    var sum: Float = 0
    for i in 0..<frameLength {
      let sample = channelData[i]
      sum += sample * sample
    }

    let rms = sqrt(sum / Float(frameLength))
    let db = 20 * log10(max(rms, 0.000001))

    audioLevel = db
  }
}

// MARK: - Word Detail Sheet

private struct WordDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  let word: String

  @State private var showTranslation = false
  @State private var showExplanation = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text(word)
          .font(.largeTitle)
          .fontWeight(.bold)
          .padding(.top, 40)

        Text("Tapped word")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Spacer()

        VStack(spacing: 12) {
          // Translate button
          Button {
            showTranslation = true
          } label: {
            Label("Translate", systemImage: "translate")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          // Explain button
          Button {
            showExplanation = true
          } label: {
            Label("Explain", systemImage: "sparkles")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          // Copy button
          Button {
            UIPasteboard.general.string = word
          } label: {
            Label("Copy to Clipboard", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.bottom, 40)
      }
      .navigationTitle("Word Detail")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium])
    .translationPresentation(
      isPresented: $showTranslation,
      text: word
    )
    .sheet(isPresented: $showExplanation) {
      WordExplanationSheet(
        text: word,
        context: word
      )
    }
  }
}

// MARK: - Explain Sheet

private struct ExplainSheet: View {
  @Environment(\.dismiss) private var dismiss
  let text: String

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Selected Text")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text(text)
            .font(.body)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

          Divider()

          Text("Explanation")
            .font(.caption)
            .foregroundStyle(.secondary)

          // TODO: Add AI explanation here
          Text("Explanation feature coming soon...")
            .font(.body)
            .foregroundStyle(.secondary)
            .italic()
        }
        .padding()
      }
      .navigationTitle("Explain")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            UIPasteboard.general.string = text
          } label: {
            Image(systemName: "doc.on.doc")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    RealtimeTranscriptionView()
  }
}
