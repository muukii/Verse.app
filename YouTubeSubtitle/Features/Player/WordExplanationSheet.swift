//
//  WordExplanationSheet.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/05.
//

import SwiftUI
#if os(iOS)
import SafariServices
#endif

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

// MARK: - Safari View (iOS only)

#if os(iOS)
/// SwiftUI wrapper for SFSafariViewController
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    configuration.barCollapsingEnabled = true
    let safari = SFSafariViewController(url: url, configuration: configuration)
    safari.preferredControlTintColor = .systemBlue
    return safari
  }

  func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
    // No updates needed
  }
}
#endif

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}

// MARK: - Word Explanation Sheet (Stateful Container)

/// Sheet view for displaying Apple Intelligence-generated word/phrase explanations.
/// This is the stateful container that manages async operations and state.
struct WordExplanationSheet: View {
  let text: String
  let context: String

  @Environment(\.dismiss) private var dismiss
  @State private var service = ExplanationService()
  @State private var streamedContent: String = ""
  @State private var isStreaming: Bool = false
  @State private var streamTask: Task<Void, Never>?
  @State private var followUpQuestion: String = ""
  @State private var conversationHistory: [(question: String, answer: String)] = []
  @State private var geminiURL: URL?

  var body: some View {
    WordExplanationSheetContent(
      text: text,
      context: context,
      serviceState: service.state,
      streamedContent: streamedContent,
      isStreaming: isStreaming,
      conversationHistory: conversationHistory,
      followUpQuestion: $followUpQuestion,
      onClose: { dismiss() },
      onRetry: { retryExplanation() },
      onSendFollowUp: { sendFollowUpQuestion() },
      onOpenGemini: { openInGemini() }
    )
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
    #if os(iOS)
    .sheet(item: $geminiURL) { url in
      SafariView(url: url)
        .ignoresSafeArea()
    }
    #endif
  }

  // MARK: - Actions

  private func retryExplanation() {
    streamTask?.cancel()
    streamTask = Task {
      await generateExplanation()
    }
  }

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
    // Use SFSafariViewController on iOS for in-app browsing
    geminiURL = url
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

// MARK: - Word Explanation Sheet Content (Stateless View)

/// Stateless content view for word explanations.
/// Receives all state and actions from the parent container.
struct WordExplanationSheetContent: View {
  // Input props
  let text: String
  let context: String

  // Display state
  let serviceState: ExplanationService.State
  let streamedContent: String
  let isStreaming: Bool
  let conversationHistory: [(question: String, answer: String)]

  // Bindings
  @Binding var followUpQuestion: String

  // Actions
  let onClose: () -> Void
  let onRetry: () -> Void
  let onSendFollowUp: () -> Void
  let onOpenGemini: () -> Void

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
            onClose()
          }
        }

        ToolbarItem(placement: .primaryAction) {
          HStack(spacing: 12) {
            // Open in Gemini button
            Button {
              onOpenGemini()
            } label: {
              Image(systemName: "sparkle.magnifyingglass")
            }

            if serviceState == .loading || isStreaming {
              ProgressView()
            }
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
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
        switch serviceState {
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
          onSendFollowUp()
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
    // Preprocess: Convert single newlines to double newlines for proper line breaks
    // In Markdown, single \n is ignored; \n\n creates a paragraph break
    let preprocessed = text

    do {
      let attributed = try AttributedString(
        markdown: preprocessed,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
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
        onRetry()
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
}

// MARK: - Preview

#Preview("Loading") {
  WordExplanationSheetContent(
    text: "nevertheless",
    context: "Nevertheless, we decided to proceed with the plan.",
    serviceState: .loading,
    streamedContent: "",
    isStreaming: true,
    conversationHistory: [],
    followUpQuestion: .constant(""),
    onClose: {},
    onRetry: {},
    onSendFollowUp: {},
    onOpenGemini: {}
  )
}

#Preview("With Explanation") {
  WordExplanationSheetContent(
    text: "serendipity",
    context: "It was pure serendipity that we met.",
    serviceState: .success("**Serendipity** means the occurrence of events by chance in a happy or beneficial way.\n\n## Translation\n偶然の幸運、思いがけない発見\n\n## Explanation\nThis word describes finding something good without specifically looking for it."),
    streamedContent: "",
    isStreaming: false,
    conversationHistory: [],
    followUpQuestion: .constant(""),
    onClose: {},
    onRetry: {},
    onSendFollowUp: {},
    onOpenGemini: {}
  )
}

#Preview("Error State") {
  WordExplanationSheetContent(
    text: "ephemeral",
    context: "The beauty of cherry blossoms is ephemeral.",
    serviceState: .error("Model not available. Please try again later."),
    streamedContent: "",
    isStreaming: false,
    conversationHistory: [],
    followUpQuestion: .constant(""),
    onClose: {},
    onRetry: {},
    onSendFollowUp: {},
    onOpenGemini: {}
  )
}

#Preview("With Conversation History") {
  WordExplanationSheetContent(
    text: "ubiquitous",
    context: "Smartphones have become ubiquitous in modern society.",
    serviceState: .success("**Ubiquitous** means present, appearing, or found everywhere."),
    streamedContent: "",
    isStreaming: false,
    conversationHistory: [
      (question: "Can you give me more examples?", answer: "Sure! Here are more examples:\n- Coffee shops are ubiquitous in urban areas.\n- Wi-Fi has become ubiquitous in public spaces."),
      (question: "What's the origin of this word?", answer: "The word comes from Latin 'ubique' meaning 'everywhere'.")
    ],
    followUpQuestion: .constant(""),
    onClose: {},
    onRetry: {},
    onSendFollowUp: {},
    onOpenGemini: {}
  )
}

#Preview("Rich Markdown") {
  WordExplanationSheetContent(
    text: "nevertheless",
    context: "Nevertheless, we decided to proceed with the plan.",
    serviceState: .success("""
      ## Input

      nevertheless

      ## Translation

      それにもかかわらず、しかしながら

      ## Explanation

      **Nevertheless** is an adverb used to introduce a statement that contrasts with or seems to contradict something that has been said previously.

      ### Usage Examples

      - The weather was terrible. *Nevertheless*, we enjoyed our trip.
      - He was tired; *nevertheless*, he continued working.

      ### Synonyms

      - however
      - nonetheless
      - even so
      - still
      - yet

      ### Register

      This word is considered **formal** and is commonly used in *written English* and *academic contexts*.
      """),
    streamedContent: "",
    isStreaming: false,
    conversationHistory: [],
    followUpQuestion: .constant(""),
    onClose: {},
    onRetry: {},
    onSendFollowUp: {},
    onOpenGemini: {}
  )
}
