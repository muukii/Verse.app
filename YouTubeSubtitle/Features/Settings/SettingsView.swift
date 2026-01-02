//
//  SettingsView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/04.
//

import AppIntents
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(VideoItemService.self) private var historyService
  @State private var explanationService = ExplanationService()
  @State private var foundationModelService = FoundationModelService()
  @State private var showClearHistoryConfirmation = false

  var body: some View {
    NavigationStack {
      List {
        // MARK: - Apple Intelligence for Word Explanations
        Section {
          ExplanationAppleIntelligenceRow(service: explanationService)
        } header: {
          Text("Word Explanations")
        } footer: {
          ExplanationAppleIntelligenceFooter(service: explanationService)
        }

        // MARK: - Apple Intelligence for Vocabulary Auto-Fill
        Section {
          VocabularyAppleIntelligenceRow(service: foundationModelService)
        } header: {
          Text("Vocabulary Auto-Fill")
        } footer: {
          VocabularyAppleIntelligenceFooter(service: foundationModelService)
        }

        // MARK: - Transcription
        Section {
          AutoTranscribeToggle()
        } header: {
          Text("Transcription")
        } footer: {
          Text("Automatically transcribe videos when YouTube subtitles don't have word timing.")
        }

        // MARK: - Siri & Shortcuts
        Section {
          SiriTipView(intent: OpenYouTubeVideoIntent())
        } header: {
          Text("Siri")
        } footer: {
          Text("Use Siri to quickly open YouTube videos with subtitles.")
        }

        Section {
          ShortcutsLink()
            .shortcutsLinkStyle(.automaticOutline)
        } header: {
          Text("Shortcuts")
        } footer: {
          Text("Create custom shortcuts with the Shortcuts app.")
        }

        // MARK: - Data Management
        Section {
          Button(role: .destructive) {
            showClearHistoryConfirmation = true
          } label: {
            Label {
              Text("Clear History")
            } icon: {
              Image(systemName: "trash")
                .foregroundStyle(.red)
            }
          }
        } header: {
          Text("Data")
        } footer: {
          Text("Remove all watched videos from history. This cannot be undone.")
        }

        // MARK: - Feature Flags (DEBUG only)
        #if DEBUG
        FeatureFlagsSettingsView()
        #endif

        // MARK: - Developer / Experimental
        Section {
          NavigationLink {
            VocabularyListView()
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("Vocabulary")
                Text("Save and review words from subtitles")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "text.book.closed")
                .foregroundStyle(.blue)
            }
          }

          NavigationLink {
            PlaylistListView()
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("Playlists")
                Text("Organize videos into collections")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(.orange)
            }
          }

          NavigationLink {
            RealtimeTranscriptionView()
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("Live Transcription")
                Text("Real-time speech-to-text from microphone")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "waveform.badge.mic")
                .foregroundStyle(.purple)
            }
          }
        } header: {
          Text("Experimental")
        } footer: {
          Text("Features under development. Live Transcription requires iOS 26+ and physical device.")
        }
      }
      .navigationTitle("Settings")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .confirmationDialog(
        "Clear History",
        isPresented: $showClearHistoryConfirmation,
        titleVisibility: .visible
      ) {
        Button("Clear All History", role: .destructive) {
          Task {
            try? await historyService.clearAllHistory()
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Are you sure you want to clear all history? This will remove all watched videos and cannot be undone.")
      }
    }
  }
}

// MARK: - Explanation Apple Intelligence Row

private struct ExplanationAppleIntelligenceRow: View {
  let service: ExplanationService

  var body: some View {
    HStack {
      Label {
        Text("Apple Intelligence")
      } icon: {
        Image(systemName: "apple.logo")
          .foregroundStyle(.primary)
      }

      Spacer()

      statusBadge
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    let availability = service.checkAvailability()

    switch availability {
    case .available:
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Available")
          .foregroundStyle(.secondary)
      }
      .font(.caption)

    case .unavailable(let reason):
      HStack(spacing: 4) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.orange)
        Text(statusText(for: reason))
          .foregroundStyle(.secondary)
      }
      .font(.caption)
    }
  }

  private func statusText(for reason: ExplanationService.Availability.UnavailabilityReason) -> String {
    switch reason {
    case .deviceNotEligible:
      return "Not Supported"
    case .appleIntelligenceNotEnabled:
      return "Enable in Settings"
    case .modelNotReady:
      return "Downloading..."
    case .unknown:
      return "Unavailable"
    }
  }
}

// MARK: - Explanation Apple Intelligence Footer

private struct ExplanationAppleIntelligenceFooter: View {
  let service: ExplanationService

  var body: some View {
    let availability = service.checkAvailability()

    switch availability {
    case .available:
      Text("Apple Intelligence is ready to use for word explanations.")

    case .unavailable(let reason):
      switch reason {
      case .deviceNotEligible:
        Text("This device does not support Apple Intelligence. Word explanations require a compatible device.")
      case .appleIntelligenceNotEnabled:
        Text("Enable Apple Intelligence in System Settings > Apple Intelligence & Siri to use word explanations.")
      case .modelNotReady:
        Text("Apple Intelligence model is being downloaded by the system. Word explanations will be available when ready.")
      case .unknown:
        Text("Apple Intelligence is not available for word explanations.")
      }
    }
  }
}

// MARK: - Vocabulary Apple Intelligence Row

private struct VocabularyAppleIntelligenceRow: View {
  let service: FoundationModelService

  var body: some View {
    HStack {
      Label {
        Text("Apple Intelligence")
      } icon: {
        Image(systemName: "apple.logo")
          .foregroundStyle(.primary)
      }

      Spacer()

      statusBadge
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    let availability = service.checkAvailability()

    switch availability {
    case .available:
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Available")
          .foregroundStyle(.secondary)
      }
      .font(.caption)

    case .unavailable:
      HStack(spacing: 4) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.orange)
        Text("Unavailable")
          .foregroundStyle(.secondary)
      }
      .font(.caption)
    }
  }
}

// MARK: - Vocabulary Apple Intelligence Footer

private struct VocabularyAppleIntelligenceFooter: View {
  let service: FoundationModelService

  var body: some View {
    let availability = service.checkAvailability()

    switch availability {
    case .available:
      Text("Apple Intelligence is ready to use for vocabulary auto-fill.")

    case .unavailable(let reason):
      Text("Apple Intelligence is not available: \(reason)")
    }
  }
}

// MARK: - Auto Transcribe Toggle

private struct AutoTranscribeToggle: View {
  @AppStorage("autoTranscribeEnabled") private var autoTranscribeEnabled: Bool = true

  var body: some View {
    Toggle(isOn: $autoTranscribeEnabled) {
      Label {
        Text("Auto-Transcribe")
      } icon: {
        Image(systemName: "waveform")
          .foregroundStyle(.blue)
      }
    }
  }
}

#Preview {
  SettingsView()
}
