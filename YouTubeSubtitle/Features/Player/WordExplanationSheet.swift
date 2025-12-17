//
//  WordExplanationSheet.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/05.
//

import SwiftUI

// MARK: - Word Explanation Sheet

/// Sheet view for displaying LLM-generated word/phrase explanations.
struct WordExplanationSheet: View {
  let text: String
  let context: String

  @Environment(\.dismiss) private var dismiss
  @State private var service = LLMService()
  @State private var streamedContent: String = ""
  @State private var isStreaming: Bool = false
  @State private var streamTask: Task<Void, Never>?
  @State private var showsInstructionViewer: Bool = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Selected text display
          selectedTextSection

          Divider()

          // Explanation section
          explanationSection
        }
        .padding()
      }
      .navigationTitle("Explanation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }

        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: 12) {
            Button {
              showsInstructionViewer = true
            } label: {
              Image(systemName: "info.circle")
            }

            if service.state == .loading || isStreaming {
              ProgressView()
            }
          }
        }
      }
      .sheet(isPresented: $showsInstructionViewer) {
        InstructionViewerSheet(service: service)
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .onAppear {
      // Start streaming explanation when sheet appears
      streamTask = Task {
        await generateExplanation()
      }
    }
    .onDisappear {
      // Cancel streaming when sheet is dismissed
      streamTask?.cancel()
      streamTask = nil
      // Also cancel any ongoing generation in the service
      service.cancelCurrentGeneration()
    }
  }

  // MARK: - Subviews

  private var selectedTextSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Selected Text", systemImage: "text.quote")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(text)
        .font(.title3)
        .fontWeight(.semibold)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))

      if !context.isEmpty && context != text {
        Text("Context: \"\(context)\"")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
  }

  @ViewBuilder
  private var explanationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Explanation", systemImage: "sparkles")
        .font(.caption)
        .foregroundStyle(.secondary)

      Group {
        switch service.state {
        case .idle:
          placeholderView

        case .loading:
          if streamedContent.isEmpty {
            loadingView
          } else {
            explanationText(streamedContent)
          }

        case .downloadingModel(let progress):
          VStack(spacing: 8) {
            ProgressView(value: progress)
            Text("Downloading model... \(Int(progress * 100))%")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding()

        case .success(let explanation):
          explanationText(explanation)

        case .error(let message):
          errorView(message: message)
        }
      }
    }
  }

  private var placeholderView: some View {
    Text("Generating explanation...")
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
  }

  private var loadingView: some View {
    HStack(spacing: 8) {
      ProgressView()
      Text("Generating explanation...")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }

  private func explanationText(_ text: String) -> some View {
    Text(markdownAttributedString(from: text))
      .font(.body)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .textSelection(.enabled)
  }

  /// Convert Markdown string to AttributedString for rendering.
  /// Falls back to plain text if Markdown parsing fails.
  private func markdownAttributedString(from text: String) -> AttributedString {
    do {
      var attributed = try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
      // Apply default font to maintain consistency
      attributed.font = .body
      return attributed
    } catch {
      // Fallback to plain text if markdown parsing fails
      return AttributedString(text)
    }
  }

  private func errorView(message: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Unable to generate explanation")
          .fontWeight(.medium)
      }

      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)

      Button {
        // Cancel existing task if any
        streamTask?.cancel()
        // Start new streaming task
        streamTask = Task {
          await generateExplanation()
        }
      } label: {
        Label("Try Again", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color.orange.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Actions

  private func generateExplanation() async {
    // Check if task was already cancelled
    guard !Task.isCancelled else { return }

    // Check availability first
    let availability = service.checkAvailability()
    print("[LLM] Availability: \(availability), preferredBackend: \(service.preferredBackend)")

    guard case .available(let backend) = availability else {
      if case .unavailable(let reason) = availability {
        service.state = .error(reason.localizedDescription)
      }
      return
    }

    print("[LLM] Using backend: \(backend)")

    // Use streaming for better UX
    isStreaming = true
    streamedContent = ""

    do {
      for try await content in service.streamExplanation(text: text, context: context) {
        // Check for cancellation in the stream loop
        guard !Task.isCancelled else {
          isStreaming = false
          return
        }
        streamedContent = content
        print("[LLM] Received content chunk: \(content.prefix(50))...")
      }
      print("[LLM] Stream completed successfully")
    } catch {
      print("[LLM] Stream error: \(error)")
      // Error is already handled by the service
      // Don't update state if task was cancelled
      guard !Task.isCancelled else { return }
    }

    isStreaming = false
  }
}

// MARK: - Instruction Viewer Sheet

/// Sheet view for displaying the current instruction settings used in explanation.
private struct InstructionViewerSheet: View {
  let service: LLMService

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        // MARK: - System Instruction
        Section {
          Text(service.effectiveSystemInstruction)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        } header: {
          HStack {
            Text("System Instruction")
            Spacer()
            if service.customSystemInstruction.isEmpty {
              Text("Default")
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
              Text("Custom")
                .font(.caption2)
                .foregroundStyle(.blue)
            }
          }
        }

        // MARK: - User Prompt Template
        Section {
          Text(service.effectiveUserPromptTemplate)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        } header: {
          HStack {
            Text("User Prompt Template")
            Spacer()
            if service.customUserPromptTemplate.isEmpty {
              Text("Default")
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
              Text("Custom")
                .font(.caption2)
                .foregroundStyle(.blue)
            }
          }
        }

        // MARK: - Backend Info
        Section {
          LabeledContent("Backend", value: service.preferredBackend.displayName)
          if service.preferredBackend == .mlx {
            if let model = LLMService.availableMLXModels.first(where: { $0.id == service.selectedMLXModelId }) {
              LabeledContent("Model", value: model.name)
            }
          }
        } header: {
          Text("Configuration")
        }
      }
      .navigationTitle("Instruction Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}

// MARK: - Preview

#Preview("Loading") {
  WordExplanationSheet(
    text: "nevertheless",
    context: "Nevertheless, we decided to proceed with the plan."
  )
}

#Preview("With Explanation") {
  struct PreviewWrapper: View {
    var body: some View {
      WordExplanationSheet(
        text: "serendipity",
        context: "It was pure serendipity that we met."
      )
    }
  }
  return PreviewWrapper()
}
