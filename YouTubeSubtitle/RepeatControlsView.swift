//
//  RepeatControlsView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit

struct RepeatControlsView: View {
  let currentTime: Double
  @Binding var repeatStartTime: Double?
  @Binding var repeatEndTime: Double?
  @Binding var isRepeating: Bool

  var body: some View {
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
          Text(repeatStartTime.map { TimeFormatting.formatTime($0) } ?? "--:--")
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
          Text(repeatEndTime.map { TimeFormatting.formatTime($0) } ?? "--:--")
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
}
