//
//  SubtitleSectionView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit
import YoutubeTranscript

struct SubtitleSectionView: View {
  let player: YouTubePlayer?
  let transcripts: [TranscriptResponse]
  let isLoadingTranscripts: Bool
  let transcriptError: String?
  let currentTime: Double
  @Binding var scrollPosition: Double?
  let backgroundColor: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "captions.bubble")
          .foregroundStyle(.secondary)
        Text("Subtitles")
          .font(.headline)

        Spacer()

        if !transcripts.isEmpty {
          Text("\(transcripts.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      // Content
      if isLoadingTranscripts {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading subtitles...")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = transcriptError {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 40))
            .foregroundStyle(.orange)
          Text("Failed to load subtitles")
            .font(.headline)
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if transcripts.isEmpty {
        ContentUnavailableView(
          "No Subtitles",
          systemImage: "text.bubble",
          description: Text("No subtitles available for this video")
        )
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(transcripts.enumerated()), id: \.offset) { index, transcript in
              SubtitleRowView(
                transcript: transcript,
                isCurrent: isCurrentSubtitle(offset: transcript.offset),
                onTap: {
                  if let player = player {
                    jumpToSubtitle(player: player, offset: transcript.offset)
                  }
                }
              )
            }
          }
          .padding(12)
        }
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onChange(of: currentTime) { _, _ in
          updateScrollPosition()
        }
      }
    }
    .background(backgroundColor)
  }

  private func isCurrentSubtitle(offset: Double) -> Bool {
    guard !transcripts.isEmpty else { return false }

    if let currentIndex = transcripts.firstIndex(where: { $0.offset > currentTime }) {
      if currentIndex > 0 {
        let previousTranscript = transcripts[currentIndex - 1]
        return previousTranscript.offset == offset
      }
      return false
    } else {
      if let lastTranscript = transcripts.last {
        return lastTranscript.offset == offset && currentTime >= offset
      }
      return false
    }
  }

  private func updateScrollPosition() {
    guard !transcripts.isEmpty else { return }

    if let currentIndex = transcripts.firstIndex(where: { $0.offset > currentTime }), currentIndex > 0 {
      let currentTranscript = transcripts[currentIndex - 1]
      scrollPosition = currentTranscript.offset
    } else if let lastTranscript = transcripts.last, currentTime >= lastTranscript.offset {
      scrollPosition = lastTranscript.offset
    }
  }

  private func jumpToSubtitle(player: YouTubePlayer, offset: Double) {
    Task {
      try? await player.seek(to: Measurement(value: offset, unit: UnitDuration.seconds), allowSeekAhead: true)
    }
  }
}
