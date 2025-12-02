//
//  SubtitleListView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/02.
//

import SwiftUI

// MARK: - Subtitle List View

struct SubtitleListView: View {
  let entries: [SubtitleEntry]
  let currentTime: Double
  let isLoading: Bool
  let error: String?
  let onTap: (Double) -> Void

  @Binding var isTrackingEnabled: Bool
  @Binding var scrollPosition: ScrollPosition

  @Environment(\.colorScheme) private var colorScheme

  private var backgroundColor: Color {
    colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92)
  }

  var body: some View {
    Group {
      if isLoading {
        loadingView
      } else if let error {
        errorView(error: error)
      } else if entries.isEmpty {
        emptyView
      } else {
        subtitleList
      }
    }
    .background(backgroundColor)
  }

  // MARK: - Loading View

  private var loadingView: some View {
    VStack(spacing: 12) {
      ProgressView()
      Text("Loading subtitles...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Error View

  private func errorView(error: String) -> some View {
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
  }

  // MARK: - Empty View

  private var emptyView: some View {
    ContentUnavailableView(
      "No Subtitles",
      systemImage: "text.bubble",
      description: Text("No subtitles available for this video")
    )
  }

  // MARK: - Subtitle List

  private var subtitleList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 6) {
        ForEach(entries) { entry in
          SubtitleRowView(
            entry: entry,
            isCurrent: isCurrentSubtitle(entry: entry),
            onTap: { onTap(entry.startTime) }
          )
        }
      }
      .padding(12)
    }
    .scrollPosition($scrollPosition)
    .onScrollPhaseChange { _, newPhase in
      if newPhase == .interacting {
        isTrackingEnabled = false
      }
    }
    .onChange(of: currentTime) { _, _ in
      updateScrollPosition()
    }
  }

  // MARK: - Helper Methods

  private func isCurrentSubtitle(entry: SubtitleEntry) -> Bool {
    guard !entries.isEmpty else { return false }

    if let currentIndex = entries.firstIndex(where: { $0.startTime > currentTime }) {
      if currentIndex > 0 {
        let previousEntry = entries[currentIndex - 1]
        return previousEntry.id == entry.id
      }
      return false
    } else {
      if let lastEntry = entries.last {
        return lastEntry.id == entry.id && currentTime >= entry.startTime
      }
      return false
    }
  }

  private func updateScrollPosition() {
    guard !entries.isEmpty, isTrackingEnabled else { return }

    if let currentIndex = entries.firstIndex(where: { $0.startTime > currentTime }), currentIndex > 0 {
      let currentEntry = entries[currentIndex - 1]
      scrollPosition.scrollTo(id: currentEntry.id, anchor: .center)
    } else if let lastEntry = entries.last, currentTime >= lastEntry.startTime {
      scrollPosition.scrollTo(id: lastEntry.id, anchor: .center)
    }
  }
}

// MARK: - Subtitle Row View

struct SubtitleRowView: View {
  let entry: SubtitleEntry
  let isCurrent: Bool
  let onTap: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Time badge
      Text(formatTime(entry.startTime))
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(isCurrent ? .white : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isCurrent ? Color.red : Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 4))

      // Text content
      Text(entry.text.htmlDecoded)
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
    .id(entry.id)
    .animation(.easeInOut(duration: 0.2), value: isCurrent)
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

// MARK: - HTML Decoding Extension

extension String {
  var htmlDecoded: String {
    var result = self
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&#x27;", with: "'")
      .replacingOccurrences(of: "&#x2F;", with: "/")
      .replacingOccurrences(of: "&nbsp;", with: " ")

    // Decode numeric entities like &#8217;
    let pattern = "&#([0-9]+);"
    while let range = result.range(of: pattern, options: .regularExpression) {
      let matched = String(result[range])
      let numStr = matched.dropFirst(2).dropLast(1)
      if let code = UInt32(numStr), let scalar = Unicode.Scalar(code) {
        result.replaceSubrange(range, with: String(scalar))
      } else {
        break
      }
    }

    return result
  }
}

#Preview {
  SubtitleListView(
    entries: [
      SubtitleEntry(id: 1, startTime: 0, endTime: 3, text: "Hello, world!"),
      SubtitleEntry(id: 2, startTime: 3, endTime: 6, text: "This is a test subtitle."),
      SubtitleEntry(id: 3, startTime: 6, endTime: 9, text: "Testing the subtitle list view.")
    ],
    currentTime: 4,
    isLoading: false,
    error: nil,
    onTap: { _ in },
    isTrackingEnabled: .constant(true),
    scrollPosition: .constant(.init())
  )
}
