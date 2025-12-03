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

// MARK: - PlayerViewModel

@Observable
final class PlayerViewModel {
  let videoID: String

  var youtubePlayer: YouTubePlayer?
  var currentTime: Double = 0
  var duration: Double = 0
  var isTrackingTime: Bool = false
  var subtitleEntries: [SubtitleEntry] = []
  var currentSubtitles: Subtitles?
  var isLoadingTranscripts: Bool = false
  var transcriptError: String?
  var scrollPosition: ScrollPosition = .init()
  var isDraggingSlider: Bool = false
  var dragTime: Double = 0
  var isPlaying: Bool = false
  var isSubtitleTrackingEnabled: Bool = true
  var repeatStartTime: Double?
  var repeatEndTime: Double?
  var isRepeating: Bool = false
  var playbackRate: Double = 1.0
  var subtitleSource: SubtitleSource = .youtube

  init(videoID: String) {
    self.videoID = videoID
  }

  func loadVideo() {
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

  func fetchTranscripts(videoID: String) {
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
          self.subtitleEntries = entries
          self.currentSubtitles = subtitles
          self.subtitleSource = .youtube
          self.isLoadingTranscripts = false
        }
      } catch {
        await MainActor.run {
          self.transcriptError = error.localizedDescription
          self.isLoadingTranscripts = false
        }
      }
    }
  }

  func startTrackingTime(player: YouTubePlayer) {
    isTrackingTime = true

    Task {
      try? await Task.sleep(for: .seconds(1))

      if let videoDuration = try? await player.getDuration() {
        await MainActor.run {
          self.duration = videoDuration.converted(to: .seconds).value
        }
      }
    }

    Task {
      while isTrackingTime {
        if let time = try? await player.getCurrentTime() {
          let timeValue = time.converted(to: .seconds).value
          await MainActor.run {
            self.currentTime = timeValue
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
          self.isPlaying = (state == .playing)
        }

        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  func seek(player: YouTubePlayer, to time: Double) {
    Task {
      try? await player.seek(
        to: Measurement(value: time, unit: UnitDuration.seconds),
        allowSeekAhead: true
      )
    }
  }

  func seekBackward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = max(0, currentSeconds - 10)
        try? await player.seek(to: Measurement(value: newSeconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      }
    }
  }

  func seekForward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = currentSeconds + 10
        try? await player.seek(to: Measurement(value: newSeconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      }
    }
  }

  func togglePlayPause(player: YouTubePlayer) {
    Task {
      let state = player.playbackState
      switch state {
      case .playing:
        try? await player.pause()
        await MainActor.run { self.isPlaying = false }
      case .paused, .unstarted, .ended, .buffering, .cued:
        try? await player.play()
        await MainActor.run { self.isPlaying = true }
      case .none:
        try? await player.play()
        await MainActor.run { self.isPlaying = true }
      }
    }
  }

  func setPlaybackRate(player: YouTubePlayer, rate: Double) {
    Task {
      try? await player.set(playbackRate: rate)
      await MainActor.run {
        self.playbackRate = rate
      }
    }
  }
}

// MARK: - PlayerView

struct PlayerView: View {
  @State private var viewModel: PlayerViewModel

  init(videoID: String) {
    _viewModel = State(initialValue: PlayerViewModel(videoID: videoID))
  }

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
      viewModel.loadVideo()
    }
  }

  // MARK: - Player Section

  private var playerSection: some View {
    VStack(spacing: 0) {
      if let player = viewModel.youtubePlayer {
        YouTubePlayerView(player)
          .aspectRatio(16/9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(.horizontal, 16)
          .padding(.top, 16)

        ProgressBar(
          currentTime: viewModel.currentTime,
          duration: viewModel.duration,
          onSeek: { time in
            viewModel.seek(player: player, to: time)
          }
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)

        TimeDisplay(
          currentTime: viewModel.isDraggingSlider ? viewModel.dragTime : viewModel.currentTime,
          duration: viewModel.duration
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)

        PlaybackControls(
          isPlaying: viewModel.isPlaying,
          onBackward: { viewModel.seekBackward(player: player) },
          onForward: { viewModel.seekForward(player: player) },
          onTogglePlayPause: { viewModel.togglePlayPause(player: player) }
        )
        .padding(.top, 8)

        HStack(spacing: 24) {
          RepeatControls(
            currentTime: viewModel.currentTime,
            repeatStartTime: $viewModel.repeatStartTime,
            repeatEndTime: $viewModel.repeatEndTime,
            isRepeating: $viewModel.isRepeating
          )

          Divider()
            .frame(height: 24)

          SpeedControls(
            playbackRate: viewModel.playbackRate,
            onRateChange: { rate in
              viewModel.setPlaybackRate(player: player, rate: rate)
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
        subtitleSource: viewModel.subtitleSource,
        entryCount: viewModel.subtitleEntries.count,
        isTrackingEnabled: $viewModel.isSubtitleTrackingEnabled,
        videoID: viewModel.videoID,
        currentSubtitles: viewModel.currentSubtitles,
        onSubtitlesImported: { entries in
          viewModel.subtitleEntries = entries
          viewModel.currentSubtitles = entries.toSwiftSubtitles()
          viewModel.subtitleSource = .imported
        }
      )

      Divider()

      SubtitleListView(
        entries: viewModel.subtitleEntries,
        currentTime: viewModel.currentTime,
        isLoading: viewModel.isLoadingTranscripts,
        error: viewModel.transcriptError,
        onTap: { time in
          if let player = viewModel.youtubePlayer {
            viewModel.seek(player: player, to: time)
          }
        },
        isTrackingEnabled: $viewModel.isSubtitleTrackingEnabled,
        scrollPosition: $viewModel.scrollPosition
      )
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
