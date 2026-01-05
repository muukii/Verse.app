//
//  YouTubeVideoPlayer.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/05.
//

import Combine
import Foundation
import SwiftUI
import YouTubePlayerKit

// MARK: - YouTubeVideoPlayer

/// SwiftUI View for YouTube video playback.
/// Usage: YouTubeVideoPlayer(controller: controller)
struct YouTubeVideoPlayer: View {
  let controller: YouTubeVideoPlayerController

  var body: some View {
    YouTubePlayerView(controller.player)
  }
}

// MARK: - YouTubeVideoPlayerController

/// Controller for YouTube video playback.
/// Conforms to VideoPlayerController protocol for unified playback control.
@Observable
@MainActor
final class YouTubeVideoPlayerController: VideoPlayerController {

  // MARK: - Properties

  let player: YouTubePlayer
  private var _playbackRate: Double = 1.0

  /// Tracks if user explicitly initiated playback (to block auto-play on first seek)
  private var userInitiatedPlay: Bool = false
  private var playbackStateCancellable: AnyCancellable?

  // MARK: - Initialization

  init(videoID: String) {
    let parameters = YouTubePlayer.Parameters(
      autoPlay: false,
      language: "en",
      captionLanguage: "en"
    )
    self.player = YouTubePlayer(
      source: .video(id: videoID),
      parameters: parameters
    )

    // Block auto-play triggered by first seek
    playbackStateCancellable = player.playbackStatePublisher
      .sink { [weak self] state in
        guard let self, state == .playing, !self.userInitiatedPlay else { return }
        Task { @MainActor in
          try? await self.player.pause()
        }
      }
  }

  // MARK: - VideoPlayerController

  var isPlaying: Bool {
    player.isPlaying
  }

  var currentTime: Double {
    get async {
      guard let time = try? await player.getCurrentTime() else { return 0 }
      return time.converted(to: .seconds).value
    }
  }

  var duration: Double {
    get async {
      guard let duration = try? await player.getDuration() else { return 0 }
      return duration.converted(to: .seconds).value
    }
  }

  var playbackRate: Double {
    _playbackRate
  }

  func play() async {
    userInitiatedPlay = true
    try? await player.play()
  }

  func pause() async {
    try? await player.pause()
  }

  func seek(to time: Double) async {
    try? await player.seek(
      to: Measurement(value: time, unit: UnitDuration.seconds),
      allowSeekAhead: true
    )
  }

  func setPlaybackRate(_ rate: Double) async {
    _playbackRate = rate
    try? await player.set(playbackRate: .init(value: rate))
  }
}
