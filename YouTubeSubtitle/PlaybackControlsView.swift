//
//  PlaybackControlsView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit

struct PlaybackControlsView: View {
  let player: YouTubePlayer
  let isPlaying: Bool
  let onSeekBackward: () -> Void
  let onSeekForward: () -> Void
  let onTogglePlayPause: () -> Void

  var body: some View {
    HStack(spacing: 32) {
      // Backward 10s
      Button {
        onSeekBackward()
      } label: {
        Image(systemName: "gobackward.10")
          .font(.system(size: 24))
          .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)

      // Play/Pause
      Button {
        onTogglePlayPause()
      } label: {
        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 48))
          .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)

      // Forward 10s
      Button {
        onSeekForward()
      } label: {
        Image(systemName: "goforward.10")
          .font(.system(size: 24))
          .foregroundStyle(.primary)
      }
      .buttonStyle(.plain)
    }
  }
}
