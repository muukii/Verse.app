//
//  PlayerView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit
import YoutubeTranscript

struct PlayerView: View {
  let videoID: String

  @State private var youtubePlayer: YouTubePlayer?
  @State private var currentTime: Double = 0
  @State private var duration: Double = 0
  @State private var isTrackingTime: Bool = false
  @State private var transcripts: [TranscriptResponse] = []
  @State private var isLoadingTranscripts: Bool = false
  @State private var transcriptError: String?
  @State private var scrollPosition: Double?
  @State private var isDraggingSlider: Bool = false
  @State private var dragTime: Double = 0
  @State private var isPlaying: Bool = false
  @State private var repeatStartTime: Double?
  @State private var repeatEndTime: Double?
  @State private var isRepeating: Bool = false
  @State private var playbackRate: Double = 1.0

  @Environment(\.colorScheme) private var colorScheme

  private var backgroundColor: Color {
    colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96)
  }

  private var subtitleBackgroundColor: Color {
    colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92)
  }

  var body: some View {
    GeometryReader { geometry in
      let isWide = geometry.size.width > 900

      if isWide {
        // Wide layout: side by side
        HStack(spacing: 0) {
          playerSection
            .frame(maxWidth: .infinity)

          SubtitleSectionView(
            player: youtubePlayer,
            transcripts: transcripts,
            isLoadingTranscripts: isLoadingTranscripts,
            transcriptError: transcriptError,
            currentTime: currentTime,
            scrollPosition: $scrollPosition,
            backgroundColor: subtitleBackgroundColor
          )
          .frame(width: min(400, geometry.size.width * 0.35))
        }
      } else {
        // Narrow layout: stacked
        VStack(spacing: 0) {
          playerSection

          SubtitleSectionView(
            player: youtubePlayer,
            transcripts: transcripts,
            isLoadingTranscripts: isLoadingTranscripts,
            transcriptError: transcriptError,
            currentTime: currentTime,
            scrollPosition: $scrollPosition,
            backgroundColor: subtitleBackgroundColor
          )
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
        // Video Player
        YouTubePlayerView(player)
          .aspectRatio(16/9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(.horizontal, 16)
          .padding(.top, 16)

        // Progress Bar
        PlayerProgressBarView(
          player: player,
          currentTime: currentTime,
          duration: duration,
          repeatStartTime: repeatStartTime,
          repeatEndTime: repeatEndTime,
          isDraggingSlider: $isDraggingSlider,
          dragTime: $dragTime
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)

        // Time Display
        HStack {
          Text(TimeFormatting.formatTime(isDraggingSlider ? dragTime : currentTime))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)

          Spacer()

          Text(TimeFormatting.formatTime(duration))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)

        // Playback Controls
        PlaybackControlsView(
          player: player,
          isPlaying: isPlaying,
          onSeekBackward: { seekBackward(player: player) },
          onSeekForward: { seekForward(player: player) },
          onTogglePlayPause: { togglePlayPause(player: player) }
        )
        .padding(.top, 8)

        // Repeat Controls & Speed Controls
        HStack(spacing: 24) {
          RepeatControlsView(
            currentTime: currentTime,
            repeatStartTime: $repeatStartTime,
            repeatEndTime: $repeatEndTime,
            isRepeating: $isRepeating
          )

          Divider()
            .frame(height: 24)

          SpeedControlsView(
            player: player,
            playbackRate: $playbackRate
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

    // Start tracking time
    startTrackingTime(player: player)

    // Fetch transcripts
    fetchTranscripts(videoID: videoID)
  }

  private func fetchTranscripts(videoID: String) {
    isLoadingTranscripts = true
    transcriptError = nil
    transcripts = []

    Task {
      do {
        let config = TranscriptConfig(lang: "en")
        let fetchedTranscripts = try await YoutubeTranscript.fetchTranscript(for: videoID, config: config)

        await MainActor.run {
          transcripts = fetchedTranscripts
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

    // Fetch duration once when video loads
    Task {
      // Wait a bit for video to load
      try? await Task.sleep(for: .seconds(1))

      if let videoDuration = try? await player.getDuration() {
        await MainActor.run {
          duration = videoDuration.converted(to: .seconds).value
        }
      }
    }

    // Start periodic updates for current time and playback state
    Task {
      while isTrackingTime {
        if let time = try? await player.getCurrentTime() {
          let timeValue = time.converted(to: .seconds).value
          await MainActor.run {
            currentTime = timeValue
          }

          // Check for repeat loop-back
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

        // Track playback state
        let state = player.playbackState
        await MainActor.run {
          isPlaying = (state == .playing)
        }

        // Update every 0.5 seconds
        try? await Task.sleep(for: .milliseconds(500))
      }
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
}

#Preview {
  PlayerView(videoID: "oRc4sndVaWo")
}
