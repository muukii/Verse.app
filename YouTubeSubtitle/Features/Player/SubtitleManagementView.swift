//
//  SubtitleManagementView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/01.
//

import SwiftUI
import SwiftSubtitles
import UniformTypeIdentifiers

/// View for managing subtitles and playback options
struct SubtitleManagementView: View {
  let videoID: String
  let subtitles: Subtitles?
  let localFileURL: URL?
  let playbackSource: PlaybackSource
  let onSubtitlesImported: (Subtitles) -> Void
  let onPlaybackSourceChange: (PlaybackSource) -> Void

  @State private var showExportSheet = false
  @State private var showImportPicker = false
  @State private var exportFormat: SubtitleFormat = .srt
  @State private var showSaveConfirmation = false
  @State private var errorMessage: String?
  @State private var showError = false

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Menu {
      // MARK: - Playback Source (only if local file exists)
      if localFileURL != nil {
        Section("Playback Source") {
          Button {
            onPlaybackSourceChange(.youtube)
          } label: {
            Label(
              "YouTube",
              systemImage: playbackSource == .youtube ? "checkmark" : "play.rectangle"
            )
          }

          Button {
            onPlaybackSourceChange(.local)
          } label: {
            Label(
              "Local File",
              systemImage: playbackSource == .local ? "checkmark" : "internaldrive"
            )
          }
        }
      }

      // MARK: - Subtitle Management
      Section("Subtitles") {
        // Save to local storage
        if subtitles != nil {
          Button {
            saveSubtitles()
          } label: {
            Label("Save Subtitles", systemImage: "square.and.arrow.down")
          }

          // Export to file
          Button {
            showExportSheet = true
          } label: {
            Label("Export...", systemImage: "square.and.arrow.up")
          }
        }

        // Import from file
        Button {
          showImportPicker = true
        } label: {
          Label("Import Subtitle File...", systemImage: "doc.badge.plus")
        }

        // Load from storage
        let savedFormats = SubtitleStorage.shared.listSavedFormats(videoID: videoID)
        if !savedFormats.isEmpty {
          Menu {
            ForEach(savedFormats) { format in
              Button {
                loadSavedSubtitles(format: format)
              } label: {
                Text(format.rawValue)
              }
            }
          } label: {
            Label("Load Saved", systemImage: "folder")
          }
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 20))
    }
    .sheet(isPresented: $showExportSheet) {
      ExportSheetView(
        videoID: videoID,
        subtitles: subtitles,
        selectedFormat: $exportFormat
      )
    }
    .fileImporter(
      isPresented: $showImportPicker,
      allowedContentTypes: subtitleContentTypes,
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
    .alert("Saved", isPresented: $showSaveConfirmation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Subtitles saved successfully")
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Unknown error occurred")
    }
  }

  private var subtitleContentTypes: [UTType] {
    [
      UTType(filenameExtension: "srt") ?? .plainText,
      UTType(filenameExtension: "vtt") ?? .plainText,
      UTType(filenameExtension: "sbv") ?? .plainText,
      UTType(filenameExtension: "csv") ?? .commaSeparatedText,
      UTType(filenameExtension: "lrc") ?? .plainText,
      UTType(filenameExtension: "ttml") ?? .xml,
      .plainText
    ]
  }

  private func saveSubtitles() {
    guard let subtitles else { return }

    do {
      try SubtitleStorage.shared.save(subtitles, videoID: videoID, format: .srt)
      showSaveConfirmation = true
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func loadSavedSubtitles(format: SubtitleFormat) {
    do {
      let subtitles = try SubtitleStorage.shared.load(videoID: videoID, format: format)
      onSubtitlesImported(subtitles)
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }

      // Start accessing security-scoped resource
      guard url.startAccessingSecurityScopedResource() else {
        errorMessage = "Cannot access the file"
        showError = true
        return
      }

      defer { url.stopAccessingSecurityScopedResource() }

      do {
        let subtitles = try SubtitleAdapter.decode(from: url)

        // Also save to storage
        if let format = SubtitleFormat.allCases.first(where: {
          url.pathExtension.lowercased() == $0.fileExtension
        }) {
          try? SubtitleStorage.shared.save(subtitles, videoID: videoID, format: format)
        }

        onSubtitlesImported(subtitles)
      } catch {
        errorMessage = error.localizedDescription
        showError = true
      }

    case .failure(let error):
      errorMessage = error.localizedDescription
      showError = true
    }
  }
}

// MARK: - Export Sheet View

struct ExportSheetView: View {
  let videoID: String
  let subtitles: Subtitles?
  @Binding var selectedFormat: SubtitleFormat

  @State private var showExporter = false
  @State private var exportContent = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Export Format") {
          Picker("Format", selection: $selectedFormat) {
            ForEach(SubtitleFormat.allCases) { format in
              Text(format.rawValue).tag(format)
            }
          }
          .pickerStyle(.menu)

          Text("File extension: .\(selectedFormat.fileExtension)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section {
          Button("Export") {
            prepareExport()
          }
          .disabled(subtitles == nil)
        }
      }
      .navigationTitle("Export Subtitles")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
      .fileExporter(
        isPresented: $showExporter,
        document: SubtitleDocument(content: exportContent, format: selectedFormat),
        contentType: UTType(filenameExtension: selectedFormat.fileExtension) ?? .plainText,
        defaultFilename: "\(videoID).\(selectedFormat.fileExtension)"
      ) { result in
        switch result {
        case .success:
          dismiss()
        case .failure(let error):
          print("Export failed: \(error)")
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 300, minHeight: 200)
    #endif
  }

  private func prepareExport() {
    guard let subtitles else { return }

    do {
      exportContent = try SubtitleAdapter.encode(subtitles, format: selectedFormat)
      showExporter = true
    } catch {
      print("Failed to encode: \(error)")
    }
  }
}

// MARK: - Subtitle Document for Export

struct SubtitleDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }

  let content: String
  let format: SubtitleFormat

  init(content: String, format: SubtitleFormat) {
    self.content = content
    self.format = format
  }

  init(configuration: ReadConfiguration) throws {
    content = ""
    format = .srt
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let data = content.data(using: .utf8) ?? Data()
    return FileWrapper(regularFileWithContents: data)
  }
}

#Preview {
  SubtitleManagementView(
    videoID: "test123",
    subtitles: nil,
    localFileURL: nil,
    playbackSource: .youtube,
    onSubtitlesImported: { _ in },
    onPlaybackSourceChange: { _ in }
  )
}
