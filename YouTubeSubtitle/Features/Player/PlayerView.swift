//
//  PlayerView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import ObjectEdge
import SwiftData
import SwiftSubtitles
import SwiftUI
import YouTubeKit
import YouTubePlayerKit
import YoutubeTranscript

struct PlayerView: View {
  let videoID: String

  @Environment(\.modelContext) private var modelContext
  @ObjectEdge private var model = PlayerModel()

  @State private var youtubePlayer: YouTubePlayer?
  @State private var isTrackingTime: Bool = false
  @State private var currentSubtitles: Subtitles?
  @State private var isLoadingTranscripts: Bool = false
  @State private var transcriptError: String?
  @State private var scrollPosition: ScrollPosition = .init()
  @State private var isSubtitleTrackingEnabled: Bool = true
  @AppStorage("backwardSeekInterval") private var backwardSeekInterval: Double =
    3
  @AppStorage("forwardSeekInterval") private var forwardSeekInterval: Double = 3
  @State private var subtitleSource: SubtitleSource = .youtube
  @State private var showDownloadView: Bool = false

  @State private var height: CGFloat = 0
  @State private var isShowingSheet: Bool = true

  var body: some View {
    if let player = youtubePlayer {

      VStack(spacing: 0) {
        VideoPlayer(player: player)    
        
        VStack {

          subtitleSection

          PlayerControls(
            model: model,
            backwardSeekInterval: backwardSeekInterval,
            forwardSeekInterval: forwardSeekInterval,
            onSeek: { time in seek(player: player, to: time) },
            onSeekBackward: { seekBackward(player: player) },
            onSeekForward: { seekForward(player: player) },
            onTogglePlayPause: { togglePlayPause(player: player) },
            onRateChange: { rate in setPlaybackRate(player: player, rate: rate)
            },
            onBackwardSeekIntervalChange: { interval in
              backwardSeekInterval = interval
            },
            onForwardSeekIntervalChange: { interval in
              forwardSeekInterval = interval
            }
          )
        }
        
      }
     
      .background(.appPlayerBackground)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: 16) {
            SubtitleManagementView(
              videoID: videoID,
              subtitles: currentSubtitles,
              onSubtitlesImported: { subtitles in
                currentSubtitles = subtitles
                subtitleSource = .imported
              }
            )

            Button {
              showDownloadView = true
            } label: {
              Label("Download", systemImage: "arrow.down.circle")
            }
          }
        }
      }
      .sheet(isPresented: $showDownloadView) {
        NavigationStack {
          DownloadView(videoID: videoID)
        }
      }
      .onDisappear { 
        isShowingSheet = false
      }
    } else {
      ProgressView()
        .onAppear {
          loadVideo()
        }
    }
  }

  // MARK: - Subtitle Section

  private var subtitleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      SubtitleHeader(subtitleSource: subtitleSource)

      SubtitleListView(
        cues: currentSubtitles?.cues ?? [],
        currentTime: model.currentTime,
        isLoading: isLoadingTranscripts,
        error: transcriptError,
        onTap: { time in
          if let player = youtubePlayer {
            seek(player: player, to: time)
          }
        },
        onSetRepeatA: { time in
          model.repeatStartTime = time
          if let end = model.repeatEndTime, time < end {
            model.isRepeating = true
          }
        },
        onSetRepeatB: { time in
          model.repeatEndTime = time
          if let start = model.repeatStartTime, time > start {
            model.isRepeating = true
          }
        },
        isTrackingEnabled: $isSubtitleTrackingEnabled,
        scrollPosition: $scrollPosition
      )
      .overlay(alignment: .bottomTrailing) {
        Button {
          isSubtitleTrackingEnabled.toggle()
        } label: {
          Image(systemName: isSubtitleTrackingEnabled ? "arrow.up.left.circle.fill" : "arrow.up.left.circle")
            .font(.system(size: 28))
            .foregroundStyle(isSubtitleTrackingEnabled ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .padding(12)
      }
    }
  }

  // MARK: - Private Methods

  private func loadVideo() {
    // Prevent multiple loads
    guard youtubePlayer == nil else { return }

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
    currentSubtitles = nil

    Task {
      // Check cache first
      let descriptor = FetchDescriptor<VideoHistoryItem>(
        predicate: #Predicate { $0.videoID == videoID }
      )

      if let historyItem = try? modelContext.fetch(descriptor).first,
         let cached = historyItem.cachedSubtitles,
         !cached.cues.isEmpty {
        await MainActor.run {
          currentSubtitles = cached
          subtitleSource = .youtube
          isLoadingTranscripts = false
        }
        return
      }

      // Fetch from network
      do {
        let config = TranscriptConfig(lang: nil)
        let fetchedTranscripts = try await YoutubeTranscript.fetchTranscript(
          for: videoID,
          config: config
        )

        let subtitles = fetchedTranscripts.toSwiftSubtitles()

        // Save to cache
        if let historyItem = try? modelContext.fetch(descriptor).first {
          historyItem.cachedSubtitles = subtitles
        }

        await MainActor.run {
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
          model.duration = videoDuration.converted(to: .seconds).value
        }
      }
    }

    Task {
      while isTrackingTime {
        if let time = try? await player.getCurrentTime() {
          let timeValue = time.converted(to: .seconds).value
          await MainActor.run {
            model.currentTime = timeValue
          }

          if let loopStartTime = model.checkRepeatLoop() {
            try? await player.seek(
              to: Measurement(value: loopStartTime, unit: UnitDuration.seconds),
              allowSeekAhead: true
            )
          }
        }

        let state = player.playbackState
        await MainActor.run {
          model.isPlaying = (state == .playing)
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
        let newSeconds = max(0, currentSeconds - backwardSeekInterval)
        try? await player.seek(
          to: Measurement(value: newSeconds, unit: UnitDuration.seconds),
          allowSeekAhead: true
        )
      }
    }
  }

  private func seekForward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = currentSeconds + forwardSeekInterval
        try? await player.seek(
          to: Measurement(value: newSeconds, unit: UnitDuration.seconds),
          allowSeekAhead: true
        )
      }
    }
  }

  private func togglePlayPause(player: YouTubePlayer) {
    Task {
      let state = player.playbackState
      switch state {
      case .playing:
        try? await player.pause()
        await MainActor.run { model.isPlaying = false }
      case .paused, .unstarted, .ended, .buffering, .cued:
        try? await player.play()
        await MainActor.run { model.isPlaying = true }
      case .none:
        try? await player.play()
        await MainActor.run { model.isPlaying = true }
      }
    }
  }

  private func setPlaybackRate(player: YouTubePlayer, rate: Double) {
    Task {
      try? await player.set(playbackRate: rate)
      await MainActor.run {
        model.playbackRate = rate
      }
    }
  }
}

// MARK: - Nested Components

extension PlayerView {

  // MARK: - VideoPlayer

  struct VideoPlayer: View {
    let player: YouTubePlayer

    var body: some View {
      YouTubePlayerView(player)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
  }

  // MARK: - PlayerControls

  struct PlayerControls: View {
    let model: PlayerModel
    let backwardSeekInterval: Double
    let forwardSeekInterval: Double
    let onSeek: (Double) -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onTogglePlayPause: () -> Void
    let onRateChange: (Double) -> Void
    let onBackwardSeekIntervalChange: (Double) -> Void
    let onForwardSeekIntervalChange: (Double) -> Void

    var body: some View {
      VStack(spacing: 0) {
        ProgressBar(
          currentTime: model.currentTime,
          duration: model.duration,
          onSeek: onSeek
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)

        TimeDisplay(
          currentTime: model.displayTime,
          duration: model.duration
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)

        PlaybackControls(
          isPlaying: model.isPlaying,
          backwardSeekInterval: backwardSeekInterval,
          forwardSeekInterval: forwardSeekInterval,
          onBackward: onSeekBackward,
          onForward: onSeekForward,
          onTogglePlayPause: onTogglePlayPause,
          onBackwardSeekIntervalChange: onBackwardSeekIntervalChange,
          onForwardSeekIntervalChange: onForwardSeekIntervalChange
        )
        .padding(.top, 8)

        HStack(spacing: 24) {
          RepeatControls(model: model)

          Divider()
            .frame(height: 24)

          SpeedControls(
            playbackRate: model.playbackRate,
            onRateChange: onRateChange
          )
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
      }
    }
  }

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
        backgroundColor: Color.gray.opacity(0.3)
      )
      .frame(height: 16)
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
    let backwardSeekInterval: Double
    let forwardSeekInterval: Double
    let onBackward: () -> Void
    let onForward: () -> Void
    let onTogglePlayPause: () -> Void
    let onBackwardSeekIntervalChange: (Double) -> Void
    let onForwardSeekIntervalChange: (Double) -> Void

    private let availableIntervals: [Double] = [3, 5, 10, 15, 30]

    var body: some View {
      HStack(spacing: 32) {
        Button(action: onBackward) {
          seekIcon(direction: .backward, interval: backwardSeekInterval)
        }
        .buttonStyle(.glass)
        .contextMenu {
          seekIntervalMenu(
            currentInterval: backwardSeekInterval,
            onChange: onBackwardSeekIntervalChange
          )
        }

        Button(action: onTogglePlayPause) {
          Image(
            systemName: isPlaying ? "pause.fill" : "play.fill"
          )
          .font(.system(size: 32))
        }
        .buttonStyle(.glass)

        Button(action: onForward) {
          seekIcon(direction: .forward, interval: forwardSeekInterval)
        }
        .buttonStyle(.glass)
        .contextMenu {
          seekIntervalMenu(
            currentInterval: forwardSeekInterval,
            onChange: onForwardSeekIntervalChange
          )
        }
      }
    }

    private enum SeekDirection {
      case backward, forward
    }

    @ViewBuilder
    private func seekIcon(direction: SeekDirection, interval: Double)
      -> some View
    {
      let prefix = direction == .backward ? "gobackward" : "goforward"
      let symbolName: String = {
        switch interval {
        case 5: return "\(prefix).5"
        case 10: return "\(prefix).10"
        case 15: return "\(prefix).15"
        case 30: return "\(prefix).30"
        case 45: return "\(prefix).45"
        case 60: return "\(prefix).60"
        default:
          return prefix
        }
      }()

      if interval == 3 || ![5, 10, 15, 30, 45, 60].contains(Int(interval)) {
        // Custom view for 3 seconds or other non-standard intervals
        ZStack {
          Image(systemName: prefix)
            .font(.system(size: 24))
          Text("\(Int(interval))")
            .font(.system(size: 8, weight: .bold))
            .offset(y: 1)
        }
        .foregroundStyle(.primary)
      } else {
        Image(systemName: symbolName)
          .font(.system(size: 24))
          .foregroundStyle(.primary)
      }
    }

    @ViewBuilder
    private func seekIntervalMenu(
      currentInterval: Double,
      onChange: @escaping (Double) -> Void
    ) -> some View {
      ForEach(availableIntervals, id: \.self) { interval in
        Button {
          onChange(interval)
        } label: {
          HStack {
            Text("\(Int(interval)) seconds")
            if interval == currentInterval {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    }
  }

  // MARK: - RepeatControls

  struct RepeatControls: View {
    let model: PlayerModel

    var body: some View {
      HStack(spacing: 16) {
        Button {
          model.setRepeatStartToCurrent()
        } label: {
          HStack(spacing: 4) {
            Text("A")
              .font(.system(.caption, design: .rounded).bold())
            Text(model.repeatStartTime.map { formatTime($0) } ?? "--:--")
              .font(.system(.caption, design: .monospaced))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(
            model.repeatStartTime != nil
              ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15)
          )
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)

        Button {
          model.setRepeatEndToCurrent()
        } label: {
          HStack(spacing: 4) {
            Text("B")
              .font(.system(.caption, design: .rounded).bold())
            Text(model.repeatEndTime.map { formatTime($0) } ?? "--:--")
              .font(.system(.caption, design: .monospaced))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(
            model.repeatEndTime != nil
              ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15)
          )
          .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)

        Button {
          model.toggleRepeat()
        } label: {
          Image(
            systemName: model.isRepeating ? "repeat.circle.fill" : "repeat.circle"
          )
          .font(.system(size: 24))
          .foregroundStyle(model.isRepeating ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!model.canToggleRepeat)

        if model.repeatStartTime != nil || model.repeatEndTime != nil {
          Button {
            model.clearRepeat()
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

    private let availableRates: [Double] = [
      0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0,
    ]

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

    var body: some View {
      Group {
        if subtitleSource != .youtube {
          HStack {
            Text("(\(subtitleSource.displayName))")
              .font(.caption)
              .foregroundStyle(.orange)
            Spacer()
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
      }
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
  NavigationStack {
    PlayerView(videoID: "oRc4sndVaWo")
  }
}
