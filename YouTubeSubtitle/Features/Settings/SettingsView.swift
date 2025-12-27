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
  @State private var llmService = LLMService()
  @State private var showClearHistoryConfirmation = false

  var body: some View {
    NavigationStack {
      List {
        // MARK: - AI Backend Selection
        Section {
          BackendPicker(service: llmService)
        } header: {
          Text("AI Backend")
        } footer: {
          Text("Choose which AI engine to use for word explanations.")
        }

        // MARK: - Apple Intelligence Status
        Section {
          AppleIntelligenceRow(service: llmService)
        } header: {
          Text("Apple Intelligence")
        } footer: {
          AppleIntelligenceFooter(service: llmService)
        }

        // MARK: - Local Model (MLX)
        Section {
          MLXModelRow(service: llmService)
        } header: {
          Text("Local Model")
        } footer: {
          Text("Uses Qwen 2.5 1.5B model (~800MB). Downloads automatically on first use.")
        }

        // MARK: - Explain Instructions
        Section {
          NavigationLink {
            ExplainInstructionSettingsView()
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("Explain Instructions")
                Text("Customize AI prompts for word explanations")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "text.bubble")
                .foregroundStyle(.blue)
            }
          }
        } header: {
          Text("AI Prompts")
        } footer: {
          Text("Customize the system instruction and prompt template used for explanations.")
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

// MARK: - Backend Picker

private struct BackendPicker: View {
  @Bindable var service: LLMService

  var body: some View {
    Picker("Preferred Engine", selection: Binding(
      get: { service.preferredBackend },
      set: { service.preferredBackend = $0 }
    )) {
      ForEach(LLMService.Backend.allCases) { backend in
        Text(backend.displayName).tag(backend)
      }
    }
  }
}

// MARK: - Apple Intelligence Row

private struct AppleIntelligenceRow: View {
  let service: LLMService

  var body: some View {
    HStack {
      Label {
        Text("Status")
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
    let availability = service.checkAppleIntelligenceAvailability()

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

  private func statusText(for reason: LLMService.Availability.UnavailabilityReason) -> String {
    switch reason {
    case .deviceNotEligible:
      return "Not Supported"
    case .appleIntelligenceNotEnabled:
      return "Enable in Settings"
    case .modelNotReady:
      return "Downloading..."
    case .mlxModelNotLoaded:
      return "N/A"
    case .unknown:
      return "Unavailable"
    }
  }
}

// MARK: - Apple Intelligence Footer

private struct AppleIntelligenceFooter: View {
  let service: LLMService

  var body: some View {
    let availability = service.checkAppleIntelligenceAvailability()

    switch availability {
    case .available:
      Text("Apple Intelligence is ready to use.")

    case .unavailable(let reason):
      switch reason {
      case .deviceNotEligible:
        Text("This device does not support Apple Intelligence.")
      case .appleIntelligenceNotEnabled:
        Text("Enable Apple Intelligence in System Settings > Apple Intelligence & Siri.")
      case .modelNotReady:
        Text("Apple Intelligence model is being downloaded by the system.")
      default:
        Text("Apple Intelligence is not available.")
      }
    }
  }
}

// MARK: - MLX Model Row

private struct MLXModelRow: View {
  @Bindable var service: LLMService

  var body: some View {
    Picker("Model", selection: Binding(
      get: { service.selectedMLXModelId },
      set: { service.selectedMLXModelId = $0 }
    )) {
      ForEach(LLMService.availableMLXModels) { model in
        HStack {
          Text(model.name)
          Spacer()
          Text(model.size)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(model.id)
      }
    }
    .pickerStyle(.navigationLink)
  }
}

#Preview {
  SettingsView()
}
