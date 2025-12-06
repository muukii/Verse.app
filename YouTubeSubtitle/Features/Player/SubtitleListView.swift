//
//  SubtitleListView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/02.
//

@preconcurrency import SwiftSubtitles
import SwiftUI
import RichText
import Translation

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
  let isLoading: Bool
  let transcriptionState: TranscriptionService.TranscriptionState
  let error: String?
  let onAction: (SubtitleAction) -> Void

  var body: some View {
    SubtitleListView(
      cues: cues,
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
}

// MARK: - Subtitle Scroll Content

/// Isolated component that re-renders when currentCueID changes.
/// Since currentCueID only changes when the subtitle changes (every few seconds),
/// this prevents re-renders every 500ms when currentTime updates.
private struct SubtitleScrollContent: View {
  let cues: [Subtitles.Cue]
  let currentCueID: Subtitles.Cue.ID?
  let onAction: (SubtitleAction) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 6) {
        ForEach(cues) { cue in
          SubtitleRowView(
            cue: cue,
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
              }
            }
          )
        }
      }
      .scrollTargetLayout()
      .padding(12)
    }
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
  }

  let cue: Subtitles.Cue
  let isCurrent: Bool
  let onAction: (Action) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Time badge - tappable to seek
      Button {
        onAction(.tap)
      } label: {
        Text(formatTime(cue.startTimeSeconds))
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(isCurrent ? .white : .secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(isCurrent ? Color.red : Color.gray.opacity(0.2))
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
      .buttonStyle(.plain)

      // Text content with selection support
      TextView {
        cue.text.htmlDecoded
      }
      .font(.subheadline)
      .foregroundStyle(isCurrent ? .primary : .secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onTapGesture {
        onAction(.tap)
      }

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
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isCurrent ? Color.red.opacity(0.15) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          isCurrent ? Color.red.opacity(0.3) : Color.clear,
          lineWidth: 1
        )
    )
    .id(cue.id)
    .animation(.easeInOut(duration: 0.2), value: isCurrent)
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
