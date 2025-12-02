//
//  SpeedControlsView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit

struct SpeedControlsView: View {
  let player: YouTubePlayer
  @Binding var playbackRate: Double

  private let availablePlaybackRates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "speedometer")
        .foregroundStyle(.secondary)
        .font(.system(size: 14))

      Menu {
        ForEach(availablePlaybackRates, id: \.self) { rate in
          Button {
            setPlaybackRate(rate: rate)
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

  private func setPlaybackRate(rate: Double) {
    Task {
      try? await player.set(playbackRate: rate)
      await MainActor.run {
        playbackRate = rate
      }
    }
  }
}
