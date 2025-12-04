//
//  PlayerView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import SwiftSubtitles
import TouchSlider
import YouTubePlayerKit
import YoutubeTranscript

struct PlayerView: View {
  let videoID: String

  @State private var youtubePlayer: YouTubePlayer?
  @State private var currentTime: Double = 0
  @State private var duration: Double = 0
  @State private var isTrackingTime: Bool = false
  @State private var subtitleEntries: [SubtitleEntry] = []
  @State private var currentSubtitles: Subtitles?
  @State private var isLoadingTranscripts: Bool = false
  @State private var transcriptError: String?
  @State private var scrollPosition: ScrollPosition = .init()
  @State private var isDraggingSlider: Bool = false
  @State private var dragTime: Double = 0
  @State private var isPlaying: Bool = false
  @State private var isSubtitleTrackingEnabled: Bool = true
  @State private var repeatStartTime: Double?
  @State private var repeatEndTime: Double?
  @State private var isRepeating: Bool = false
  @State private var playbackRate: Double = 1.0
  @State private var subtitleSource: SubtitleSource = .youtube

  @Environment(\.colorScheme) private var colorScheme

  private var backgroundColor: Color {
    colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96)
  }

  var body: some View {
    GeometryReader { geometry in
      let isWide = geometry.size.width > 900

      if isWide {
        HStack(spacing: 0) {
          playerSection
            .frame(maxWidth: .infinity)

          subtitleSection
            .frame(width: min(400, geometry.size.width * 0.35))
        }
      } else {
        VStack(spacing: 0) {
          playerSection

          subtitleSection
            .frame(maxHeight: geometry.size.height * 0.4)
        }
      }
    }
    .background(backgroundColor)
    .onAppear {
      loadVideo()
    }
  }

  // MARK: - Player Section

  private var playerSection: some View {
    VStack(spacing: 0) {
      if let player = youtubePlayer {
        YouTubePlayerView(player)
          .aspectRatio(16/9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(.horizontal, 16)
          .padding(.top, 16)

        ProgressBar(
          currentTime: currentTime,
          duration: duration,
          onSeek: { time in
            seek(player: player, to: time)
          }
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)

        TimeDisplay(
          currentTime: isDraggingSlider ? dragTime : currentTime,
          duration: duration
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)

        PlaybackControls(
          isPlaying: isPlaying,
          onBackward: { seekBackward(player: player) },
          onForward: { seekForward(player: player) },
          onTogglePlayPause: { togglePlayPause(player: player) }
        )
        .padding(.top, 8)

        if !subtitleEntries.isEmpty {
          SubtitleNavigationControls(
            onPrevious: { seekToPreviousSubtitle(player: player) },
            onNext: { seekToNextSubtitle(player: player) }
          )
          .padding(.top, 8)
        }

        HStack(spacing: 24) {
          RepeatControls(
            currentTime: currentTime,
            repeatStartTime: $repeatStartTime,
            repeatEndTime: $repeatEndTime,
            isRepeating: $isRepeating
          )

          Divider()
            .frame(height: 24)

          SpeedControls(
            playbackRate: playbackRate,
            onRateChange: { rate in
              setPlaybackRate(player: player, rate: rate)
            }
          )
        }
        .padding(.top, 8)
        .padding(.bottom, 16)

        Spacer(minLength: 0)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  // MARK: - Subtitle Section

  private var subtitleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      SubtitleHeader(
        subtitleSource: subtitleSource,
        entryCount: subtitleEntries.count,
        isTrackingEnabled: $isSubtitleTrackingEnabled,
        videoID: videoID,
        currentSubtitles: currentSubtitles,
        onSubtitlesImported: { entries in
          subtitleEntries = entries
          currentSubtitles = entries.toSwiftSubtitles()
          subtitleSource = .imported
        }
      )

      Divider()

      SubtitleListView(
        entries: subtitleEntries,
        currentTime: currentTime,
        isLoading: isLoadingTranscripts,
        error: transcriptError,
        onTap: { time in
          if let player = youtubePlayer {
            seek(player: player, to: time)
          }
        },
        isTrackingEnabled: $isSubtitleTrackingEnabled,
        scrollPosition: $scrollPosition
      )
    }
  }

  // MARK: - Private Methods

  private func loadVideo() {
    let configuration = YouTubePlayer.Configuration(
      captionLanguage: "en",
      language: "en"
    )
    let player = YouTubePlayer(
      source: .video(id: videoID),
      configuration: configuration
    )
    youtubePlayer = player

    startTrackingTime(player: player)
    fetchTranscripts(videoID: videoID)
  }

  private func fetchTranscripts(videoID: String) {
    isLoadingTranscripts = true
    transcriptError = nil
    subtitleEntries = []
    currentSubtitles = nil

    Task {
      do {
        let config = TranscriptConfig(lang: nil)
        let fetchedTranscripts = try await YoutubeTranscript.fetchTranscript(for: videoID, config: config)

        let entries = fetchedTranscripts.toSubtitleEntries()
        let subtitles = fetchedTranscripts.toSwiftSubtitles()

        await MainActor.run {
          subtitleEntries = entries
          currentSubtitles = subtitles
          subtitleSource = .youtube
          isLoadingTranscripts = false
        }
      } catch {
        await MainActor.run {
          transcriptError = error.localizedDescription
          isLoadingTranscripts = false
        }
      }
    }
  }

  private func startTrackingTime(player: YouTubePlayer) {
    isTrackingTime = true

    Task {
      try? await Task.sleep(for: .seconds(1))

      if let videoDuration = try? await player.getDuration() {
        await MainActor.run {
          duration = videoDuration.converted(to: .seconds).value
        }
      }
    }

    Task {
      while isTrackingTime {
        if let time = try? await player.getCurrentTime() {
          let timeValue = time.converted(to: .seconds).value
          await MainActor.run {
            currentTime = timeValue
          }

          if isRepeating,
             let startTime = repeatStartTime,
             let endTime = repeatEndTime,
             timeValue >= endTime {
            try? await player.seek(
              to: Measurement(value: startTime, unit: UnitDuration.seconds),
              allowSeekAhead: true
            )
          }
        }

        let state = player.playbackState
        await MainActor.run {
          isPlaying = (state == .playing)
        }

        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  private func seek(player: YouTubePlayer, to time: Double) {
    Task {
      try? await player.seek(
        to: Measurement(value: time, unit: UnitDuration.seconds),
        allowSeekAhead: true
      )
    }
  }

  private func seekBackward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = max(0, currentSeconds - 10)
        try? await player.seek(to: Measurement(value: newSeconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      }
    }
  }

  private func seekForward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = currentSeconds + 10
        try? await player.seek(to: Measurement(value: newSeconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      }
    }
  }

  private func togglePlayPause(player: YouTubePlayer) {
    Task {
      let state = player.playbackState
      switch state {
      case .playing:
        try? await player.pause()
        await MainActor.run { isPlaying = false }
      case .paused, .unstarted, .ended, .buffering, .cued:
        try? await player.play()
        await MainActor.run { isPlaying = true }
      case .none:
        try? await player.play()
        await MainActor.run { isPlaying = true }
      }
    }
  }

  private func setPlaybackRate(player: YouTubePlayer, rate: Double) {
    Task {
      try? await player.set(playbackRate: rate)
      await MainActor.run {
        playbackRate = rate
      }
    }
  }

  private func seekToPreviousSubtitle(player: YouTubePlayer) {
    guard !subtitleEntries.isEmpty else { return }

    // Find the previous subtitle based on current time
    // If we're more than 1 second into the current subtitle, go to its start
    // Otherwise, go to the previous subtitle's start
    if let currentIndex = subtitleEntries.lastIndex(where: { $0.startTime <= currentTime }) {
      let currentEntry = subtitleEntries[currentIndex]

      // If we're more than 1 second into the current subtitle, seek to its start
      if currentTime - currentEntry.startTime > 1.0 {
        seek(player: player, to: currentEntry.startTime)
      } else if currentIndex > 0 {
        // Go to the previous subtitle
        let previousEntry = subtitleEntries[currentIndex - 1]
        seek(player: player, to: previousEntry.startTime)
      } else {
        // Already at the first subtitle, seek to the beginning
        seek(player: player, to: subtitleEntries[0].startTime)
      }
    } else if let firstEntry = subtitleEntries.first {
      // Current time is before any subtitle, go to first subtitle
      seek(player: player, to: firstEntry.startTime)
    }
  }

  private func seekToNextSubtitle(player: YouTubePlayer) {
    guard !subtitleEntries.isEmpty else { return }

    // Find the next subtitle based on current time
    if let nextIndex = subtitleEntries.firstIndex(where: { $0.startTime > currentTime }) {
      let nextEntry = subtitleEntries[nextIndex]
      seek(player: player, to: nextEntry.startTime)
    } else if let lastEntry = subtitleEntries.last {
      // Already past all subtitles, go to the last one
      seek(player: player, to: lastEntry.startTime)
    }
  }
}

// MARK: - Nested Components

extension PlayerView {

  // MARK: - ProgressBar

  struct ProgressBar: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
      let normalizedValue = Binding<Double>(
        get: {
          guard duration > 0 else { return 0 }
          return currentTime / duration
        },
        set: { newValue in
          let clampedValue = max(0, min(1, newValue))
          let seekTime = clampedValue * duration
          onSeek(seekTime)
        }
      )

      TouchSlider(
        direction: .horizontal,
        value: normalizedValue,
        speed: 0.5,
        foregroundColor: .red,
        backgroundColor: Color.gray.opacity(0.3),
        cornerRadius: 8
      )
      .frame(height: 44)
    }
  }

  // MARK: - TimeDisplay

  struct TimeDisplay: View {
    let currentTime: Double
    let duration: Double

    var body: some View {
      HStack {
        Text(formatTime(currentTime))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)

        Spacer()

        Text(formatTime(duration))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }

    private func formatTime(_ seconds: Double) -> String {
      let totalSeconds = Int(seconds)
      let hours = totalSeconds / 3600
      let minutes = (totalSeconds % 3600) / 60
      let secs = totalSeconds % 60

      if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
      } else {
        return String(format: "%d:%02d", minutes, secs)
      }
    }
  }

  // MARK: - PlaybackControls

  struct PlaybackControls: View {
    let isPlaying: Bool
    let onBackward: () -> Void
    let onForward: () -> Void
    let onTogglePlayPause: () -> Void

    var body: some View {
      HStack(spacing: 32) {
        Button(action: onBackward) {
          Image(systemName: "gobackward.10")
            .font(.system(size: 24))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)

        Button(action: onTogglePlayPause) {
          Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)

        Button(action: onForward) {
          Image(systemName: "goforward.10")
            .font(.system(size: 24))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - SubtitleNavigationControls

  struct SubtitleNavigationControls: View {
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
      HStack(spacing: 24) {
        Button(action: onPrevious) {
          HStack(spacing: 4) {
            Image(systemName: "backward.end.fill")
              .font(.system(size: 16))
            Text("Previous")
              .font(.system(.caption, design: .rounded))
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)

        Image(systemName: "captions.bubble")
          .foregroundStyle(.secondary)
          .font(.system(size: 14))

        Button(action: onNext) {
          HStack(spacing: 4) {
            Text("Next")
              .font(.system(.caption, design: .rounded))
            Image(systemName: "forward.end.fill")
              .font(.system(size: 16))
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - RepeatControls

  struct RepeatControls: View {
    let currentTime: Double
    @Binding var repeatStartTime: Double?
    @Binding var repeatEndTime: Double?
    @Binding var isRepeating: Bool

    var body: some View {
      HStack(spacing: 16) {
        Button {
          repeatStartTime = currentTime
          if repeatEndTime == nil {
            isRepeating = false
          } else if let end = repeatEndTime, currentTime < end {
            isRepeating = true
          }
        } label: {
          HStack(spacing: 4) {
            Text("A")
              .font(.system(.caption, design: .rounded).bold())
            Text(repeatStartTime.map { formatTime($0) } ?? "--:--")
              .font(.system(.caption, design: .monospaced))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(repeatStartTime != nil ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)

        Button {
          repeatEndTime = currentTime
          if repeatStartTime == nil {
            isRepeating = false
          } else if let start = repeatStartTime, currentTime > start {
            isRepeating = true
          }
        } label: {
          HStack(spacing: 4) {
            Text("B")
              .font(.system(.caption, design: .rounded).bold())
            Text(repeatEndTime.map { formatTime($0) } ?? "--:--")
              .font(.system(.caption, design: .monospaced))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(repeatEndTime != nil ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)

        Button {
          if repeatStartTime != nil && repeatEndTime != nil {
            isRepeating.toggle()
          }
        } label: {
          Image(systemName: isRepeating ? "repeat.circle.fill" : "repeat.circle")
            .font(.system(size: 24))
            .foregroundStyle(isRepeating ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(repeatStartTime == nil || repeatEndTime == nil)

        if repeatStartTime != nil || repeatEndTime != nil {
          Button {
            repeatStartTime = nil
            repeatEndTime = nil
            isRepeating = false
          } label: {
            Image(systemName: "xmark.circle")
              .font(.system(size: 20))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
    }

    private func formatTime(_ seconds: Double) -> String {
      let totalSeconds = Int(seconds)
      let hours = totalSeconds / 3600
      let minutes = (totalSeconds % 3600) / 60
      let secs = totalSeconds % 60

      if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
      } else {
        return String(format: "%d:%02d", minutes, secs)
      }
    }
  }

  // MARK: - SpeedControls

  struct SpeedControls: View {
    let playbackRate: Double
    let onRateChange: (Double) -> Void

    private let availableRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
      HStack(spacing: 8) {
        Image(systemName: "speedometer")
          .foregroundStyle(.secondary)
          .font(.system(size: 14))

        Menu {
          ForEach(availableRates, id: \.self) { rate in
            Button {
              onRateChange(rate)
            } label: {
              HStack {
                Text(formatRate(rate))
                if rate == playbackRate {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          Text(formatRate(playbackRate))
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
      }
    }

    private func formatRate(_ rate: Double) -> String {
      if rate == 1.0 {
        return "1x"
      } else if rate == floor(rate) {
        return String(format: "%.0fx", rate)
      } else {
        return String(format: "%.2gx", rate)
      }
    }
  }

  // MARK: - SubtitleHeader

  struct SubtitleHeader: View {
    let subtitleSource: SubtitleSource
    let entryCount: Int
    @Binding var isTrackingEnabled: Bool
    let videoID: String
    let currentSubtitles: Subtitles?
    let onSubtitlesImported: ([SubtitleEntry]) -> Void

    var body: some View {
      HStack {
        Image(systemName: "captions.bubble")
          .foregroundStyle(.secondary)
        Text("Subtitles")
          .font(.headline)

        if subtitleSource != .youtube {
          Text("(\(subtitleSource.displayName))")
            .font(.caption)
            .foregroundStyle(.orange)
        }

        Spacer()

        Button {
          isTrackingEnabled.toggle()
        } label: {
          Label(
            isTrackingEnabled ? "Tracking On" : "Tracking Off",
            systemImage: isTrackingEnabled ? "eye" : "eye.slash"
          )
          .font(.caption)
          .foregroundStyle(isTrackingEnabled ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .help(isTrackingEnabled ? "Disable auto-scroll" : "Enable auto-scroll")

        if entryCount > 0 {
          Text("\(entryCount) items")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        SubtitleManagementView(
          videoID: videoID,
          subtitles: currentSubtitles,
          onSubtitlesImported: onSubtitlesImported
        )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }
}

// MARK: - Subtitle Source

enum SubtitleSource {
  case youtube
  case imported
  case saved

  var displayName: String {
    switch self {
    case .youtube: return "YouTube"
    case .imported: return "Imported"
    case .saved: return "Saved"
    }
  }
}

#Preview {
  PlayerView(videoID: "oRc4sndVaWo")
}
