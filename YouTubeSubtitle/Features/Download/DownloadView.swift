//
//  DownloadView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/04.
//

import SwiftData
import SwiftUI
import YouTubeKit

struct DownloadView: View {
  let videoID: String

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var streams: [YouTubeKit.Stream] = []
  @State private var isLoadingStreams: Bool = false
  @State private var streamError: (any Error)?

  @State private var selectedStream: YouTubeKit.Stream?
  @State private var downloadState: DownloadState = .idle
  @State private var downloadProgress: Double = 0
  @State private var downloadedFileURL: URL?

  enum DownloadState: Equatable {
    case idle
    case downloading
    case completed
    case failed(String)
  }

  /// Only show progressive MP4 streams (AVPlayer compatible)
  private var availableStreams: [YouTubeKit.Stream] {
    streams.filter { $0.isProgressive && $0.fileExtension == .mp4 }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Content
      ScrollView {
        VStack(spacing: 24) {
          // Quality Selection
          qualitySelectionSection

          // Download Progress (when downloading or completed)
          if downloadState != .idle {
            downloadStatusSection
          }
        }
        .padding(20)
      }

      // Bottom Button
      downloadButton
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Download")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") {
          dismiss()
        }
      }
    }
    .task {
      await loadStreams()
    }
  }

  // MARK: - Quality Selection Section

  private var qualitySelectionSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Select Quality")
        .font(.headline)
        .foregroundStyle(.primary)

      if isLoadingStreams {
        loadingView
      } else if let error = streamError {
        errorView(error: error)
      } else if availableStreams.isEmpty {
        emptyView
      } else {
        VStack(spacing: 8) {
          ForEach(availableStreams, id: \.url) { stream in
            QualityOptionRow(
              stream: stream,
              isSelected: selectedStream?.url == stream.url,
              onSelect: { selectedStream = stream }
            )
          }
        }
      }
    }
  }

  private var loadingView: some View {
    HStack(spacing: 12) {
      ProgressView()
      Text("Loading available qualities...")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private func errorView(error: any Error) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 40))
        .foregroundStyle(.orange)
      Text("Failed to load")
        .font(.headline)
      Text(error.localizedDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("Retry") {
        Task { await loadStreams() }
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
  }

  private var emptyView: some View {
    VStack(spacing: 12) {
      Image(systemName: "arrow.down.circle.dotted")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("No downloadable formats")
        .font(.headline)
      Text("This video doesn't have compatible formats for download.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
  }

  // MARK: - Download Status Section

  private var downloadStatusSection: some View {
    VStack(spacing: 12) {
      switch downloadState {
      case .idle:
        EmptyView()

      case .downloading:
        VStack(spacing: 8) {
          ProgressView(value: downloadProgress)
            .tint(.blue)
          HStack {
            Text("Downloading...")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(downloadProgress * 100))%")
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))

      case .completed:
        HStack(spacing: 12) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24))
            .foregroundStyle(.green)
          VStack(alignment: .leading, spacing: 2) {
            Text("Download Complete")
              .font(.subheadline.weight(.medium))
            if let url = downloadedFileURL {
              Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
        }
        .padding(16)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))

      case .failed(let message):
        HStack(spacing: 12) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 24))
            .foregroundStyle(.red)
          VStack(alignment: .leading, spacing: 2) {
            Text("Download Failed")
              .font(.subheadline.weight(.medium))
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
    }
  }

  // MARK: - Download Button

  private var downloadButton: some View {
    VStack(spacing: 0) {
      Divider()
      Button {
        Task { await startDownload() }
      } label: {
        HStack(spacing: 8) {
          if downloadState == .downloading {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: "arrow.down.circle.fill")
          }
          Text(downloadButtonTitle)
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canDownload)
      .padding(20)
    }
    .background(Color(.systemGroupedBackground))
  }

  private var downloadButtonTitle: String {
    switch downloadState {
    case .idle:
      return "Download"
    case .downloading:
      return "Downloading..."
    case .completed:
      return "Downloaded"
    case .failed:
      return "Retry Download"
    }
  }

  private var canDownload: Bool {
    guard selectedStream != nil else { return false }
    switch downloadState {
    case .idle, .failed:
      return true
    case .downloading, .completed:
      return false
    }
  }

  // MARK: - Methods

  private func loadStreams() async {
    isLoadingStreams = true
    streamError = nil
    streams = []

    do {
      let youtube = YouTube(videoID: videoID)
      async let fetchedStreams = youtube.streams
      let result = try await fetchedStreams

      await MainActor.run {
        // Sort by resolution (highest first)
        streams = result.sorted { lhs, rhs in
          (lhs.videoResolution ?? 0) > (rhs.videoResolution ?? 0)
        }
        isLoadingStreams = false

        // Auto-select best progressive mp4
        if let best = availableStreams.first {
          selectedStream = best
        }
      }
    } catch {
      await MainActor.run {
        streamError = error
        isLoadingStreams = false
      }
    }
  }

  private func startDownload() async {
    guard let stream = selectedStream else { return }

    await MainActor.run {
      downloadState = .downloading
      downloadProgress = 0
      downloadedFileURL = nil
    }

    do {
      let (data, _) = try await URLSession.shared.data(from: stream.url)

      let fileName = "\(videoID)_\(stream.itag).\(stream.fileExtension.rawValue)"
      let destinationURL = URL.documentsDirectory.appendingPathComponent(fileName)

      try? FileManager.default.removeItem(at: destinationURL)
      try data.write(to: destinationURL)

      // Save to history
      let descriptor = FetchDescriptor<VideoHistoryItem>(
        predicate: #Predicate { $0.videoID == videoID }
      )
      if let historyItem = try? modelContext.fetch(descriptor).first {
        historyItem.downloadedFileName = fileName
      }

      await MainActor.run {
        downloadedFileURL = destinationURL
        downloadProgress = 1.0
        downloadState = .completed
      }
    } catch {
      await MainActor.run {
        downloadState = .failed(error.localizedDescription)
      }
    }
  }
}

// MARK: - Quality Option Row

private struct QualityOptionRow: View {
  let stream: YouTubeKit.Stream
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 12) {
        // Selection indicator
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22))
          .foregroundStyle(isSelected ? .blue : .secondary)

        // Quality info
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            if let resolution = stream.videoResolution {
              Text("\(resolution)p")
                .font(.body.weight(.medium))

              if resolution >= 720 {
                Text("HD")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.blue)
                  .clipShape(RoundedRectangle(cornerRadius: 4))
              }
            }
          }

          HStack(spacing: 8) {
            Text(stream.fileExtension.rawValue.uppercased())
              .font(.caption)
              .foregroundStyle(.secondary)

            if let bitrate = stream.bitrate {
              Text("•")
                .foregroundStyle(.secondary)
              Text(formatBitrate(bitrate))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        Spacer()
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
  }

  private func formatBitrate(_ bitrate: Int) -> String {
    if bitrate >= 1_000_000 {
      return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
    } else {
      return String(format: "%.0f kbps", Double(bitrate) / 1_000)
    }
  }
}

#Preview {
  NavigationStack {
    DownloadView(videoID: "JKpsGXPqMd8")
  }
}
