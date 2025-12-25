//
//  WordExplanationSheet.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/05.
//

import SwiftUI

// MARK: - Gemini URL Builder

/// Builds URLs for opening Google Gemini with a prompt
struct GeminiURLBuilder {
  private static let baseURL = "https://gemini.google.com"
  private static let promptParameter = "prompt_text"

  /// Builds a Gemini URL with the given prompt text
  /// - Parameter prompt: The prompt text to send to Gemini
  /// - Returns: A URL if successfully built, nil otherwise
  static func buildURL(prompt: String) -> URL? {
    var components = URLComponents(string: baseURL)
    components?.queryItems = [
      URLQueryItem(name: promptParameter, value: prompt)
    ]

    if let url = components?.url {
      print("[GeminiURLBuilder] URL length: \(url.absoluteString.count)")
      return url
    }
    return nil
  }

  /// Builds a Gemini URL for asking about a word/phrase with context
  /// Uses the same prompt format as the on-device LLM (via ExplanationPrompt)
  /// - Parameters:
  ///   - text: The word or phrase to ask about
  ///   - context: The context in which the word/phrase appeared
  /// - Returns: A URL if successfully built, nil otherwise
  static func buildURL(text: String, context: String) -> URL? {
    // Use the shared ExplanationPrompt component (same format as LLMService)
    let prompt = ExplanationPrompt.buildFullPrompt(text: text, context: context)
    return buildURL(prompt: prompt)
  }
}

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
  @State private var followUpQuestion: String = ""
  @State private var conversationHistory: [(question: String, answer: String)] = []

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Main content with explanation and original text
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            // Explanation section (moved to top)
            explanationSection

            Divider()

            // Selected text display (moved to bottom)
            selectedTextSection
          }
          .padding()
        }

        // Follow-up input section
        followUpInputSection
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
            // Open in Gemini button
            if canOpenInGemini {
              Button {
                openInGemini()
              } label: {
                Image(systemName: "sparkle.magnifyingglass")
              }
            }

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

      // Show conversation history if there are follow-up exchanges
      if !conversationHistory.isEmpty {
        Divider()
          .padding(.vertical, 8)

        ForEach(Array(conversationHistory.enumerated()), id: \.offset) { index, exchange in
          VStack(alignment: .leading, spacing: 8) {
            // Follow-up question
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "person.circle.fill")
                .foregroundStyle(.blue)
              Text(exchange.question)
                .font(.body)
            }

            // Follow-up answer
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "sparkles")
                .foregroundStyle(.purple)
              Text(markdownAttributedString(from: exchange.answer))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private var followUpInputSection: some View {
    VStack(spacing: 0) {
      Divider()

      HStack(alignment: .bottom, spacing: 8) {
        TextField("Follow-up question...", text: $followUpQuestion, axis: .vertical)
          .textFieldStyle(.plain)
          .padding(8)
          .background(Color(.secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .lineLimit(1...4)
          .disabled(isStreaming)

        Button {
          sendFollowUpQuestion()
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title2)
            .foregroundStyle(followUpQuestion.isEmpty || isStreaming ? .gray : .blue)
        }
        .disabled(followUpQuestion.isEmpty || isStreaming)
      }
      .padding()
      .background(Color(.systemBackground))
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
      var attributed = try AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .full)
      )
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

  // MARK: - Computed Properties

  /// Determines if the "Open in Gemini" button should be shown
  /// Always available since we use the same prompt as on-device LLM (no need to wait for explanation)
  private var canOpenInGemini: Bool {
    return true
  }

  // MARK: - Actions

  /// Opens Google Gemini with the same prompt as on-device LLM
  private func openInGemini() {
    print("[Gemini] openInGemini() called")
    print("[Gemini] text: \(text)")
    print("[Gemini] context: \(context)")

    // Build URL using GeminiURLBuilder (same prompt format as LLMService)
    guard let url = GeminiURLBuilder.buildURL(text: text, context: context) else {
      print("[Gemini] Failed to build URL")
      return
    }

    print("[Gemini] Opening URL: \(url)")

    // Open the URL
    #if os(iOS)
    UIApplication.shared.open(url) { success in
      print("[Gemini] UIApplication.open completed, success: \(success)")
    }
    #elseif os(macOS)
    let success = NSWorkspace.shared.open(url)
    print("[Gemini] NSWorkspace.open completed, success: \(success)")
    #endif
  }

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

  private func sendFollowUpQuestion() {
    let question = followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return }

    // Clear the input field
    followUpQuestion = ""

    // Start streaming follow-up answer
    streamTask = Task {
      await generateFollowUpAnswer(question: question)
    }
  }

  private func generateFollowUpAnswer(question: String) async {
    guard !Task.isCancelled else { return }

    let availability = service.checkAvailability()
    guard case .available = availability else { return }

    isStreaming = true
    var followUpAnswer = ""

    do {
      // Create a follow-up context that includes the original text and previous conversation
      let followUpContext = buildFollowUpContext(question: question)

      for try await content in service.streamExplanation(text: question, context: followUpContext) {
        guard !Task.isCancelled else {
          isStreaming = false
          return
        }
        followUpAnswer = content
      }

      // Add the exchange to conversation history
      conversationHistory.append((question: question, answer: followUpAnswer))

    } catch {
      print("[LLM] Follow-up stream error: \(error)")
    }

    isStreaming = false
  }

  private func buildFollowUpContext(question: String) -> String {
    var context = "Original word/phrase: \"\(text)\"\n"
    context += "Original context: \"\(self.context)\"\n\n"

    // Include the initial explanation if available
    if case .success(let explanation) = service.state {
      context += "Previous explanation:\n\(explanation)\n\n"
    } else if !streamedContent.isEmpty {
      context += "Previous explanation:\n\(streamedContent)\n\n"
    }

    // Include conversation history
    if !conversationHistory.isEmpty {
      context += "Previous questions and answers:\n"
      for (index, exchange) in conversationHistory.enumerated() {
        context += "\nQ\(index + 1): \(exchange.question)\n"
        context += "A\(index + 1): \(exchange.answer)\n"
      }
    }

    return context
  }
}

// MARK: - Instruction Viewer Sheet

/// Sheet view for displaying the current instruction settings used in explanation.
private struct InstructionViewerSheet: View {
  let service: LLMService

  @Environment(\.dismiss) private var dismiss
  @State private var showsRawText: Bool = false

  var body: some View {
    NavigationStack {
      List {
        // MARK: - Display Mode Toggle
        Section {
          Toggle("Show Raw Text", isOn: $showsRawText)
        }

        // MARK: - System Instruction
        Section {
          if showsRawText {
            Text(service.effectiveSystemInstruction)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          } else {
            Text(markdownAttributedString(from: service.effectiveSystemInstruction))
              .font(.callout)
              .textSelection(.enabled)
          }
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
          if showsRawText {
            Text(service.effectiveUserPromptTemplate)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          } else {
            Text(markdownAttributedString(from: service.effectiveUserPromptTemplate))
              .font(.callout)
              .textSelection(.enabled)
          }
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

  /// Convert Markdown string to AttributedString for rendering.
  private func markdownAttributedString(from text: String) -> AttributedString {
    do {
      let attributed = try AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .full)
      )
      return attributed
    } catch {
      return AttributedString(text)
    }
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
