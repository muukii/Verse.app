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

  private let availablePlaybackRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  @Environment(\.colorScheme) private var colorScheme

  private var backgroundColor: Color {
    colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.96)
  }

  var body: some View {
    GeometryReader { geometry in
      let isWide = geometry.size.width > 900

      if isWide {
        // Wide layout: side by side
        HStack(spacing: 0) {
          playerSection
            .frame(maxWidth: .infinity)

          subtitleSection
            .frame(width: min(400, geometry.size.width * 0.35))
        }
      } else {
        // Narrow layout: stacked
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
        // Video Player
        YouTubePlayerView(player)
          .aspectRatio(16/9, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(.horizontal, 16)
          .padding(.top, 16)

        // Progress Bar
        progressBar(player: player)
          .padding(.horizontal, 16)
          .padding(.top, 12)

        // Time Display
        HStack {
          Text(formatTime(isDraggingSlider ? dragTime : currentTime))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)

          Spacer()

          Text(formatTime(duration))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)

        // Playback Controls
        playbackControls(player: player)
          .padding(.top, 8)

        // Repeat Controls & Speed Controls
        HStack(spacing: 24) {
          repeatControls(player: player)

          Divider()
            .frame(height: 24)

          speedControls(player: player)
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

  // MARK: - Progress Bar

  @ViewBuilder
  private func progressBar(player: YouTubePlayer) -> some View {
    let normalizedValue = Binding<Double>(
      get: {
        guard duration > 0 else { return 0 }
        return currentTime / duration
      },
      set: { newValue in
        let clampedValue = max(0, min(1, newValue))
        let seekTime = clampedValue * duration
        Task.detached {
          try? await player.seek(
            to: Measurement(value: seekTime, unit: UnitDuration.seconds),
            allowSeekAhead: true
          )
        }
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

  // MARK: - Playback Controls

  @ViewBuilder
  private func playbackControls(player: YouTubePlayer) -> some View {
    HStack(spacing: 32) {
      // Backward 10s
      Button {
        seekBackward(player: player)
      } label: {
        Image(systemName: "gobackward.10")
          .font(.system(size: 24))
          .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)

      // Play/Pause
      Button {
        togglePlayPause(player: player)
      } label: {
        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 48))
          .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)

      // Forward 10s
      Button {
        seekForward(player: player)
      } label: {
        Image(systemName: "goforward.10")
          .font(.system(size: 24))
          .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Repeat Controls

  @ViewBuilder
  private func repeatControls(player: YouTubePlayer) -> some View {
    HStack(spacing: 16) {
      // Set A (start) button
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

      // Set B (end) button
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

      // Repeat toggle
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

      // Clear button
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

  // MARK: - Speed Controls

  @ViewBuilder
  private func speedControls(player: YouTubePlayer) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "speedometer")
        .foregroundStyle(.secondary)
        .font(.system(size: 14))

      Menu {
        ForEach(availablePlaybackRates, id: \.self) { rate in
          Button {
            setPlaybackRate(player: player, rate: rate)
          } label: {
            HStack {
              Text(formatPlaybackRate(rate))
              if rate == playbackRate {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      } label: {
        Text(formatPlaybackRate(playbackRate))
          .font(.system(.caption, design: .monospaced))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
    }
  }

  private func formatPlaybackRate(_ rate: Double) -> String {
    if rate == 1.0 {
      return "1x"
    } else if rate == floor(rate) {
      return String(format: "%.0fx", rate)
    } else {
      return String(format: "%.2gx", rate)
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

  // MARK: - Subtitle Section

  private var subtitleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "captions.bubble")
          .foregroundStyle(.secondary)
        Text("Subtitles")
          .font(.headline)

        // Source indicator
        if subtitleSource != .youtube {
          Text("(\(subtitleSource.displayName))")
            .font(.caption)
            .foregroundStyle(.orange)
        }

        Spacer()

        // Subtitle Tracking Toggle
        Button {
          isSubtitleTrackingEnabled.toggle()
        } label: {
          Label(
            isSubtitleTrackingEnabled ? "Tracking On" : "Tracking Off",
            systemImage: isSubtitleTrackingEnabled ? "eye" : "eye.slash"
          )
          .font(.caption)
          .foregroundStyle(isSubtitleTrackingEnabled ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .help(isSubtitleTrackingEnabled ? "Disable auto-scroll" : "Enable auto-scroll")

        if !subtitleEntries.isEmpty {
          Text("\(subtitleEntries.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        // Subtitle Management Menu
        SubtitleManagementView(
          videoID: videoID,
          subtitles: currentSubtitles,
          onSubtitlesImported: { entries in
            subtitleEntries = entries
            currentSubtitles = entries.toSwiftSubtitles()
            subtitleSource = .imported
          }
        )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      // Content
      SubtitleListView(
        entries: subtitleEntries,
        currentTime: currentTime,
        isLoading: isLoadingTranscripts,
        error: transcriptError,
        onTap: { time in
          if let player = youtubePlayer {
            jumpToSubtitle(player: player, offset: time)
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
    
    // Start tracking time
    startTrackingTime(player: player)
    
    // Fetch transcripts
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

        // Convert to SubtitleEntry and SwiftSubtitles
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
  
  private func jumpToSubtitle(player: YouTubePlayer, offset: Double) {
    Task {
      try? await player.seek(to: Measurement(value: offset, unit: UnitDuration.seconds), allowSeekAhead: true)
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
