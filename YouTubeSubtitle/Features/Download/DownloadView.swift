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

  @Environment(\.modelContext) private var modelContext

  @State private var streams: [YouTubeKit.Stream] = []
  @State private var isLoadingStreams: Bool = false
  @State private var streamError: Error?

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

  var body: some View {
    List {
      // MARK: - Video Info
      Section("Video Info") {
        LabeledContent("Video ID", value: videoID)
      }

      // MARK: - Streams
      Section {
        if isLoadingStreams {
          HStack {
            ProgressView()
            Text("Loading streams...")
              .foregroundStyle(.secondary)
          }
        } else if let error = streamError {
          VStack(alignment: .leading, spacing: 8) {
            Label("Error", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
            Text(error.localizedDescription)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else if streams.isEmpty {
          Text("No streams available")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(streams.enumerated()), id: \.offset) { index, stream in
            StreamRow(
              stream: stream,
              isSelected: selectedStream.map { $0.url == stream.url } ?? false,
              onSelect: { selectedStream = stream }
            )
          }
        }
      } header: {
        HStack {
          Text("Available Streams")
          Spacer()
          Text("\(streams.count) streams")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // MARK: - Download State
      Section("Download State") {
        LabeledContent("Status") {
          switch downloadState {
          case .idle:
            Text("Idle")
              .foregroundStyle(.secondary)
          case .downloading:
            HStack {
              ProgressView()
                .controlSize(.small)
              Text("Downloading...")
            }
          case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          case .failed(let error):
            Label(error, systemImage: "xmark.circle.fill")
              .foregroundStyle(.red)
          }
        }

        if downloadState == .downloading {
          VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: downloadProgress)
            Text("\(Int(downloadProgress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if let fileURL = downloadedFileURL {
          LabeledContent("File") {
            Text(fileURL.lastPathComponent)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      // MARK: - Selected Stream Details
      if let stream = selectedStream {
        Section("Selected Stream Details") {
          LabeledContent("itag", value: "\(stream.itag)")
          LabeledContent("Type", value: stream.isProgressive ? "Progressive" : "Adaptive")
          LabeledContent("Format", value: stream.fileExtension.rawValue)
          if let resolution = stream.videoResolution {
            LabeledContent("Resolution", value: "\(resolution)p")
          }
          if let bitrate = stream.bitrate {
            LabeledContent("Bitrate", value: formatBitrate(bitrate))
          }
          LabeledContent("URL") {
            Text(stream.url.absoluteString)
              .font(.caption2)
              .lineLimit(2)
              .foregroundStyle(.secondary)
          }
        }
      }

      // MARK: - Debug Info
      Section("Debug") {
        Button("Reload Streams") {
          Task { await loadStreams() }
        }

        if !streams.isEmpty {
          Button("Print All Streams to Console") {
            for (index, stream) in streams.enumerated() {
              print("[\(index)] itag:\(stream.itag) \(stream.isProgressive ? "progressive" : "adaptive") \(stream.fileExtension.rawValue) \(stream.videoResolution.map { "\($0)p" } ?? "audio") bitrate:\(stream.bitrate ?? 0)")
            }
          }
        }
      }
    }
    .navigationTitle("Download")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await startDownload() }
        } label: {
          Label("Download", systemImage: "arrow.down.circle")
        }
        .disabled(selectedStream == nil || downloadState == .downloading)
      }
    }
    .task {
      await loadStreams()
    }
  }

  // MARK: - Methods

  private func loadStreams() async {
    isLoadingStreams = true
    streamError = nil
    streams = []

    do {
      let youtube = YouTube(videoID: videoID)
      let fetchedStreams = try await youtube.streams

      await MainActor.run {
        // Progressive streams first, then sort by resolution
        streams = fetchedStreams.sorted { lhs, rhs in
          if lhs.isProgressive != rhs.isProgressive {
            return lhs.isProgressive
          }
          return (lhs.videoResolution ?? 0) > (rhs.videoResolution ?? 0)
        }
        isLoadingStreams = false

        // Auto-select best progressive mp4
        if let best = streams.first(where: { $0.isProgressive && $0.fileExtension == .mp4 }) {
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

      print("Downloaded to: \(destinationURL.path)")
    } catch {
      await MainActor.run {
        downloadState = .failed(error.localizedDescription)
      }
    }
  }

  private func formatBitrate(_ bitrate: Int) -> String {
    if bitrate >= 1_000_000 {
      return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
    } else {
      return String(format: "%.0f kbps", Double(bitrate) / 1_000)
    }
  }

  private func formatFileSize(_ bytes: Int) -> String {
    if bytes >= 1_000_000_000 {
      return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    } else if bytes >= 1_000_000 {
      return String(format: "%.2f MB", Double(bytes) / 1_000_000)
    } else {
      return String(format: "%.0f KB", Double(bytes) / 1_000)
    }
  }
}

// MARK: - Stream Row

private struct StreamRow: View {
  let stream: YouTubeKit.Stream
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(stream.fileExtension.rawValue.uppercased())
              .font(.caption.bold())
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.blue.opacity(0.2))
              .clipShape(RoundedRectangle(cornerRadius: 4))

            if stream.isProgressive {
              Text("Progressive")
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            if let resolution = stream.videoResolution {
              Text("\(resolution)p")
                .font(.caption.bold())
            } else {
              Text("Audio")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          HStack(spacing: 8) {
            Text("itag: \(stream.itag)")
              .font(.caption2)
              .foregroundStyle(.secondary)

            if let bitrate = stream.bitrate {
              Text(formatBitrate(bitrate))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.blue)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private func formatFileSize(_ bytes: Int) -> String {
    if bytes >= 1_000_000 {
      return String(format: "%.1f MB", Double(bytes) / 1_000_000)
    } else {
      return String(format: "%.0f KB", Double(bytes) / 1_000)
    }
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
