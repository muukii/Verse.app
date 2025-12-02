//
//  PlayerProgressBarView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit

struct PlayerProgressBarView: View {
  let player: YouTubePlayer
  let currentTime: Double
  let duration: Double
  let repeatStartTime: Double?
  let repeatEndTime: Double?
  @Binding var isDraggingSlider: Bool
  @Binding var dragTime: Double

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let progress = duration > 0 ? (isDraggingSlider ? dragTime : currentTime) / duration : 0

      ZStack(alignment: .leading) {
        // Background track
        Capsule()
          .fill(Color.gray.opacity(0.3))
          .frame(height: 4)

        // Repeat range indicator
        if let startTime = repeatStartTime,
           let endTime = repeatEndTime,
           duration > 0 {
          let startProgress = startTime / duration
          let endProgress = endTime / duration
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange.opacity(0.4))
            .frame(width: max(0, width * (endProgress - startProgress)), height: 6)
            .offset(x: width * startProgress)
        }

        // Progress fill
        Capsule()
          .fill(Color.red)
          .frame(width: max(0, width * progress), height: 4)

        // Thumb
        Circle()
          .fill(Color.red)
          .frame(width: isDraggingSlider ? 16 : 12, height: isDraggingSlider ? 16 : 12)
          .offset(x: max(0, width * progress - (isDraggingSlider ? 8 : 6)))
          .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
      }
      .frame(height: 20)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            isDraggingSlider = true
            let newProgress = max(0, min(1, value.location.x / width))
            dragTime = newProgress * duration
          }
          .onEnded { value in
            let newProgress = max(0, min(1, value.location.x / width))
            let seekTime = newProgress * duration
            Task {
              try? await player.seek(
                to: Measurement(value: seekTime, unit: UnitDuration.seconds),
                allowSeekAhead: true
              )
            }
            isDraggingSlider = false
          }
      )
    }
    .frame(height: 20)
  }
}
