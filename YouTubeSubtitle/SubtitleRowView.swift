//
//  SubtitleRowView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YoutubeTranscript

struct SubtitleRowView: View {
  let transcript: TranscriptResponse
  let isCurrent: Bool
  let onTap: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Time badge
      Text(TimeFormatting.formatTime(transcript.offset))
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(isCurrent ? .white : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isCurrent ? Color.red : Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 4))

      // Text content
      Text(transcript.text.htmlDecoded)
        .font(.subheadline)
        .foregroundStyle(isCurrent ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isCurrent ? Color.red.opacity(0.15) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(isCurrent ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      onTap()
    }
    .id(transcript.offset)
    .animation(.easeInOut(duration: 0.2), value: isCurrent)
  }
}
