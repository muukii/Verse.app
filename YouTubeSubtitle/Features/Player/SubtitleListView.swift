//
//  SubtitleListView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/02.
//

import CoreMedia
import Speech
@preconcurrency import SwiftSubtitles
import SwiftUI
import Translation
import UIKit

// MARK: - Transcribing View

/// Modern, animated view showing transcription progress with detailed state feedback
struct TranscribingView: View {
  let state: TranscriptionService.TranscriptionState

  var body: some View {
    VStack(spacing: 24) {
      // Icon with pulse animation
      iconView
        .font(.system(size: 64))
        .symbolEffect(.pulse, options: .repeating)

      // Status text
      VStack(spacing: 8) {
        Text(mainMessage)
          .font(.title3.bold())
          .foregroundStyle(.primary)

        Text(subMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      // Progress bar (only shown during transcription)
      if case .transcribing(let progress) = state {
        VStack(spacing: 8) {
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              // Background track
              RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 8)

              // Progress fill with gradient
              RoundedRectangle(cornerRadius: 8)
                .fill(
                  LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )
                .frame(width: max(0, geometry.size.width * progress), height: 8)
                .animation(.smooth(duration: 0.3), value: progress)
            }
          }
          .frame(height: 8)

          // Percentage text
          Text("\(Int(progress * 100))%")
            .font(.system(.caption, design: .monospaced).bold())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 300)
      }
    }
    .padding(.horizontal, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var iconView: some View {
    switch state {
    case .idle:
      Image(systemName: "waveform")
        .foregroundStyle(.gray)
    case .preparingAssets:
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(
          LinearGradient(
            colors: [.blue, .cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    case .transcribing:
      Image(systemName: "mic.circle.fill")
        .foregroundStyle(
          LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  private var mainMessage: String {
    switch state {
    case .idle:
      return "Preparing..."
    case .preparingAssets:
      return "Downloading Speech Model"
    case .transcribing:
      return "Transcribing Audio"
    case .completed:
      return "Completed"
    case .failed:
      return "Transcription Failed"
    }
  }

  private var subMessage: String {
    switch state {
    case .idle:
      return "Getting ready to transcribe"
    case .preparingAssets:
      return "Downloading the speech recognition model for offline use"
    case .transcribing(let progress):
      let percentage = Int(progress * 100)
      return "Converting speech to text... \(percentage)% complete"
    case .completed:
      return "Subtitles are ready"
    case .failed(let message):
      return message
    }
  }
}

// MARK: - Subtitle List View Container

/// Container that connects SubtitleListView to PlayerModel.
/// This isolates model observation so only this view re-renders when model.currentTime changes,
/// preventing unnecessary re-renders of the parent PlayerView.
struct SubtitleListViewContainer: View {
  let model: PlayerModel
  let cues: [Subtitles.Cue]
  /// Attributed texts with audioTimeRange attributes for word-level highlighting.
  /// Array indices correspond to cue positions (0-indexed).
  let attributedTexts: [AttributedString]?
  let isLoading: Bool
  let transcriptionState: TranscriptionService.TranscriptionState
  let error: String?
  let onAction: (SubtitleAction) -> Void

  var body: some View {
    SubtitleListView(
      cues: cues,
      attributedTexts: attributedTexts,
      currentTime: model.currentTime,
      currentCueID: currentCueID,
      isLoading: isLoading,
      transcriptionState: transcriptionState,
      error: error,
      onAction: onAction
    )
  }

  /// Compute the current cue ID based on currentTime.
  /// This only changes when the active subtitle changes, not every 500ms.
  private var currentCueID: Subtitles.Cue.ID? {
    let currentTime = model.currentTime
    guard !cues.isEmpty else { return nil }

    if let currentIndex = cues.firstIndex(where: {
      $0.startTimeSeconds > currentTime
    }) {
      if currentIndex > 0 {
        return cues[currentIndex - 1].id
      }
      return nil
    } else {
      if let lastCue = cues.last, currentTime >= lastCue.startTimeSeconds {
        return lastCue.id
      }
      return nil
    }
  }
}

// MARK: - Subtitle List View

struct SubtitleListView: View {
  let cues: [Subtitles.Cue]
  let attributedTexts: [AttributedString]?
  let currentTime: Double
  let currentCueID: Subtitles.Cue.ID?
  let isLoading: Bool
  let transcriptionState: TranscriptionService.TranscriptionState
  let error: String?
  let onAction: (SubtitleAction) -> Void

  @State var isTrackingEnabled: Bool = true

  var body: some View {
    Group {
      if isLoading {
        TranscribingView(state: transcriptionState)
      } else if let error {
        errorView(error: error)
      } else if cues.isEmpty {
        emptyView
      } else {
        subtitleList
          .overlay(alignment: .bottomTrailing) {
            Button {
              isTrackingEnabled.toggle()
            } label: {
              Image(
                systemName: isTrackingEnabled
                  ? "arrow.up.left.circle.fill" : "arrow.up.left.circle"
              )
              .font(.system(size: 28))
              .foregroundStyle(isTrackingEnabled ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
          }
      }
    }

  }

  // MARK: - Error View

  private func errorView(error: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 40))
        .foregroundStyle(.orange)
      Text("Failed to load subtitles")
        .font(.headline)
      Text(error)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Empty View

  private var emptyView: some View {
    ContentUnavailableView(
      "No Subtitles",
      systemImage: "text.bubble",
      description: Text("No subtitles available for this video")
    )
  }

  // MARK: - Subtitle List

  private var subtitleList: some View {
    ScrollViewReader { proxy in
      SubtitleScrollContent(
        cues: cues,
        attributedTexts: attributedTexts,
        currentTime: currentTime,
        currentCueID: currentCueID,
        onAction: onAction
      )
      .onScrollPhaseChange { _, newPhase in
        if newPhase == .interacting {
          isTrackingEnabled = false
        }
      }
      .onChange(of: currentCueID) { _, newID in
        guard let newID, isTrackingEnabled else { return }
        withAnimation(.bouncy) {
          proxy.scrollTo(newID, anchor: .center)
        }
      }
      .onChange(of: isTrackingEnabled) { _, isEnabled in
        guard isEnabled, let currentCueID else { return }
        withAnimation(.bouncy) {
          proxy.scrollTo(currentCueID, anchor: .center)
        }
      }
    }
  }
}

// MARK: - Subtitle Action

enum SubtitleAction {
  case tap(time: Double)
  case setRepeatA(time: Double)
  case setRepeatB(time: Double)
  case explain(cue: Subtitles.Cue)
  case translate(cue: Subtitles.Cue)
  case wordTap(word: String)
}

// MARK: - Subtitle Scroll Content

/// Isolated component that re-renders when currentCueID changes.
/// Since currentCueID only changes when the subtitle changes (every few seconds),
/// this prevents re-renders every 500ms when currentTime updates.
private struct SubtitleScrollContent: View {
  let cues: [Subtitles.Cue]
  let attributedTexts: [AttributedString]?
  let currentTime: Double
  let currentCueID: Subtitles.Cue.ID?
  let onAction: (SubtitleAction) -> Void

  /// Current time as CMTime for highlighting
  private var currentCMTime: CMTime {
    CMTime(seconds: currentTime, preferredTimescale: 600)
  }

  var body: some View {
    List {
      ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
        SubtitleRowView(
          cue: cue,
          attributedText: attributedTexts?[safe: index],
          highlightTime: cue.id == currentCueID ? currentCMTime : nil,
          isCurrent: cue.id == currentCueID,
          onAction: { action in
            switch action {
            case .tap:
              onAction(.tap(time: cue.startTimeSeconds))
            case .setRepeatA:
              onAction(.setRepeatA(time: cue.startTimeSeconds))
            case .setRepeatB:
              onAction(.setRepeatB(time: cue.endTimeSeconds))
            case .explain:
              onAction(.explain(cue: cue))
            case .translate:
              onAction(.translate(cue: cue))
            case .wordTap(let word):
              onAction(.wordTap(word: word))
            }
          }
        )
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
          Button {
            onAction(.translate(cue: cue))
          } label: {
            Label("Translate", systemImage: "character.book.closed")
          }
          .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
          Button {
            onAction(.explain(cue: cue))
          } label: {
            Label("Explain", systemImage: "sparkles")
          }
          .tint(.purple)
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }
}

// MARK: - Subtitle Row View

struct SubtitleRowView: View {

  enum Action {
    case tap
    case setRepeatA
    case setRepeatB
    case explain
    case translate
    case wordTap(String)
  }

  let cue: Subtitles.Cue
  /// Attributed text with audioTimeRange for word-level highlighting (from on-device transcription)
  let attributedText: AttributedString?
  /// Current playback time for highlighting (only set when this is the current cue)
  let highlightTime: CMTime?
  let isCurrent: Bool
  let onAction: (Action) -> Void

  var body: some View {
    VStack(spacing: 4) {

      HStack {
        Button {
          onAction(.tap)
        } label: {
          Text(formatTime(cue.startTimeSeconds))
            .font(.system(.caption2, design: .default).monospacedDigit())
            .foregroundStyle(isCurrent ? .white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)        
            .background(
              ConcentricRectangle(
                corners: .concentric,
                isUniform: true
              )
              .foregroundStyle(isCurrent ? .primary : .quinary)
            )
        }
        .buttonStyle(.plain)
        
        Spacer()

      }
      .padding(6)
     
      HStack(alignment: .top, spacing: 8) {

        // Text content with selection and word tap support
        SelectableSubtitleTextView(
          text: cue.text.htmlDecoded,
          attributedText: attributedText,
          highlightTime: highlightTime,
          onWordTap: { word in
            onAction(.wordTap(word))
          }
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        menu
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 10)
    }          
    .background(
      ConcentricRectangle()
        .fill(.quaternary.opacity(isCurrent ? 1 : 0))
    )    
    .containerShape(.rect(cornerRadius: 12))   
    .id(cue.id)
    .animation(.snappy, value: isCurrent)
    .foregroundStyle(.tint)
  }

  private var menu: some View {
    // Menu button for actions
    Menu {
      Button {
        #if os(iOS)
          UIPasteboard.general.string = cue.text.htmlDecoded
        #else
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(cue.text.htmlDecoded, forType: .string)
        #endif
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }

      Button {
        onAction(.explain)
      } label: {
        Label("Explain", systemImage: "sparkles")
      }

      Button {
        onAction(.translate)
      } label: {
        Label("Translate", systemImage: "character.book.closed")
      }

      Divider()

      Button {
        onAction(.setRepeatA)
      } label: {
        Label("Set as A (Start)", systemImage: "a.circle")
      }

      Button {
        onAction(.setRepeatB)
      } label: {
        Label("Set as B (End)", systemImage: "b.circle")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 18))
        .foregroundStyle(.primary)
        .frame(width: 32, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

    if hours > 0 {
      return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, millis)
    } else {
      return String(format: "%d:%02d.%03d", minutes, secs, millis)
    }
  }
}

// MARK: - Selectable Text View (UIViewRepresentable)

private struct SelectableSubtitleTextView: UIViewRepresentable {
  let text: String
  /// Attributed text with audioTimeRange attributes for word-level highlighting
  var attributedText: AttributedString?
  /// Current playback time for highlighting (when this is the active cue)
  var highlightTime: CMTime?
  var highlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.4)
  var onWordTap: ((String) -> Void)?

  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.isEditable = false
    textView.isScrollEnabled = false
    textView.backgroundColor = .clear
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Single tap gesture for word detection
    let tapGesture = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap(_:))
    )
    tapGesture.delegate = context.coordinator

    // Make tap gesture require long press gestures to fail first
    // This prevents tap from firing when user is trying to select text
    for gesture in textView.gestureRecognizers ?? [] {
      if let longPress = gesture as? UILongPressGestureRecognizer {
        tapGesture.require(toFail: longPress)
      }
    }

    textView.addGestureRecognizer(tapGesture)

    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    if var attrText = attributedText, attrText.startIndex < attrText.endIndex {
      // Use AttributedString with potential word-level highlighting
      let fullRange = attrText.startIndex..<attrText.endIndex
      attrText[fullRange].font = UIFont.preferredFont(forTextStyle: .subheadline)
      attrText[fullRange].foregroundColor = UIColor.tintColor

      // Apply highlight if highlightTime is specified
      if let time = highlightTime {
        let timeRange = CMTimeRange(start: time, duration: CMTime(seconds: 0.5, preferredTimescale: 600))
        if let highlightRange = attrText.rangeOfAudioTimeRangeAttributes(intersecting: timeRange) {
          attrText[highlightRange].backgroundColor = highlightColor
        }
      }

      textView.attributedText = NSAttributedString(attrText)
    } else {
      // Fallback to plain text (YouTube subtitles)
      textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
      textView.textColor = UIColor.tintColor
      textView.text = text
    }
    textView.invalidateIntrinsicContentSize()
  }

  @MainActor
  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView textView: UITextView,
    context: Context
  ) -> CGSize? {
    let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
    let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: size.height)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onWordTap: onWordTap)
  }

  class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onWordTap: ((String) -> Void)?

    init(onWordTap: ((String) -> Void)?) {
      self.onWordTap = onWordTap
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let textView = gesture.view as? UITextView else { return }
      let point = gesture.location(in: textView)

      // Get tapped word using tokenizer
      if let position = textView.closestPosition(to: point),
         let range = textView.tokenizer.rangeEnclosingPosition(
           position, with: .word, inDirection: UITextDirection.storage(.forward)
         ) {
        let word = textView.text(in: range) ?? ""
        if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          onWordTap?(word)
        }
      }
    }

    // Allow tap gesture to work alongside text selection
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

// MARK: - Array Safe Subscript

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

// MARK: - HTML Decoding Extension

extension String {
  var htmlDecoded: String {
    var result =
      self
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&#x27;", with: "'")
      .replacingOccurrences(of: "&#x2F;", with: "/")
      .replacingOccurrences(of: "&nbsp;", with: " ")

    // Decode numeric entities like &#8217;
    let pattern = "&#([0-9]+);"
    while let range = result.range(of: pattern, options: .regularExpression) {
      let matched = String(result[range])
      let numStr = matched.dropFirst(2).dropLast(1)
      if let code = UInt32(numStr), let scalar = Unicode.Scalar(code) {
        result.replaceSubrange(range, with: String(scalar))
      } else {
        break
      }
    }

    return result
  }
}

#Preview("Subtitle List") {
  SubtitleListView(
    cues: [
      Subtitles.Cue(
        position: 1,
        startTime: Subtitles.Time(timeInSeconds: 0),
        endTime: Subtitles.Time(timeInSeconds: 3),
        text: "Hello, world!"
      ),
      Subtitles.Cue(
        position: 2,
        startTime: Subtitles.Time(timeInSeconds: 3),
        endTime: Subtitles.Time(timeInSeconds: 6),
        text: "This is a test subtitle."
      ),
      Subtitles.Cue(
        position: 3,
        startTime: Subtitles.Time(timeInSeconds: 6),
        endTime: Subtitles.Time(timeInSeconds: 9),
        text: "Testing the subtitle list view."
      ),
    ],
    attributedTexts: nil,
    currentTime: 4,
    currentCueID: nil,
    isLoading: false,
    transcriptionState: .idle,
    error: nil,
    onAction: { _ in }
  )
}

#Preview("Transcribing - Preparing Assets") {
  TranscribingView(state: .preparingAssets)
}

#Preview("Transcribing - In Progress") {
  TranscribingView(state: .transcribing(progress: 0.45))
}

#Preview("Transcribing - Almost Done") {
  TranscribingView(state: .transcribing(progress: 0.87))
}

#Preview("Transcribing - Completed") {
  TranscribingView(state: .completed)
}

#Preview("Transcribing - Failed") {
  TranscribingView(state: .failed("The audio file format is not supported"))
}

#Preview("SubtitleRowView") {
  SubtitleRowView(
    cue: Subtitles.Cue(
      position: 1,
      startTime: Subtitles.Time(timeInSeconds: 65.5),
      endTime: Subtitles.Time(timeInSeconds: 68.2),
      text:
        "This is the currently playing subtitle with some longer text to see how it wraps."
    ),
    attributedText: nil,
    highlightTime: nil,
    isCurrent: true,
    onAction: { _ in }
  )
  .padding()

  SubtitleRowView(
    cue: Subtitles.Cue(
      position: 2,
      startTime: Subtitles.Time(timeInSeconds: 125.75),
      endTime: Subtitles.Time(timeInSeconds: 129.0),
      text: "A subtitle that is not currently active."
    ),
    attributedText: nil,
    highlightTime: nil,
    isCurrent: false,
    onAction: { _ in }
  )
  .padding()
}
