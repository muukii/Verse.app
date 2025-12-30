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
/// Uses structured generation for translation and explanation output.
struct WordExplanationSheet: View {
  let text: String
  let context: String

  @Environment(\.dismiss) private var dismiss
  @State private var service = ExplanationService()
  @State private var translation: String = ""
  @State private var explanation: String = ""
  @State private var generationTask: Task<Void, Never>?
  @State private var geminiURL: URL?

  var body: some View {
    WordExplanationSheetContent(
      text: text,
      context: context,
      serviceState: service.state,
      translation: translation,
      explanation: explanation,
      onClose: { dismiss() },
      onRetry: { retryExplanation() },
      onOpenGemini: { openInGemini() }
    )
    .onAppear {
      // Start generating explanation when sheet appears
      generationTask = Task {
        await generateExplanation()
      }
    }
    .onDisappear {
      // Cancel generation when sheet is dismissed
      generationTask?.cancel()
      generationTask = nil
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
    generationTask?.cancel()
    translation = ""
    explanation = ""
    generationTask = Task {
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
    print("[LLM] Availability: \(availability)")

    guard case .available = availability else {
      if case .unavailable(let reason) = availability {
        service.state = .error(reason.localizedDescription)
      }
      return
    }

    print("[LLM] Apple Intelligence is available")

    do {
      // Use structured generation for better output format
      let response = try await service.generateStructuredExplanation(
        text: text,
        context: context
      )

      // Check for cancellation after generation
      guard !Task.isCancelled else { return }

      translation = response.translation
      explanation = response.explanation
      print("[LLM] Structured generation completed successfully")

    } catch {
      print("[LLM] Generation error: \(error)")
      // Error is already handled by the service
      // Don't update state if task was cancelled
      guard !Task.isCancelled else { return }
    }
  }
}

// MARK: - Word Explanation Sheet Content (Stateless View)

/// Stateless content view for word explanations.
/// Receives all state and actions from the parent container.
/// Displays structured translation and explanation sections.
struct WordExplanationSheetContent: View {
  // Input props
  let text: String
  let context: String

  // Display state
  let serviceState: ExplanationService.State
  let translation: String
  let explanation: String

  // Actions
  let onClose: () -> Void
  let onRetry: () -> Void
  let onOpenGemini: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Translation section
          translationSection

          Divider()

          // Explanation section
          explanationSection

          Divider()

          // Selected text display
          selectedTextSection
        }
        .padding()
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
          // Open in Gemini button
          Button {
            onOpenGemini()
          } label: {
            Image(systemName: "sparkle.magnifyingglass")
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
  private var translationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Translation", systemImage: "character.book.closed")
        .font(.caption)
        .foregroundStyle(.secondary)

      Group {
        switch serviceState {
        case .idle, .loading:
          if translation.isEmpty {
            loadingView
          } else {
            contentText(translation)
          }

        case .success:
          contentText(translation)

        case .error(let message):
          errorView(message: message)
        }
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
        case .idle, .loading:
          if explanation.isEmpty {
            loadingView
          } else {
            contentText(explanation)
          }

        case .success:
          contentText(explanation)

        case .error:
          // Error is shown in translation section
          EmptyView()
        }
      }
    }
  }

  private var loadingView: some View {
    HStack(spacing: 8) {
      ProgressView()
      Text("Generating...")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }

  private func contentText(_ text: String) -> some View {
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
      let attributed = try AttributedString(
        markdown: text,
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
    translation: "",
    explanation: "",
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}

#Preview("With Explanation") {
  WordExplanationSheetContent(
    text: "serendipity",
    context: "It was pure serendipity that we met.",
    serviceState: .success("## Translation\n偶然の幸運\n\n## Explanation\nThis word describes finding something good."),
    translation: "偶然の幸運、思いがけない発見",
    explanation: "**Serendipity** means the occurrence of events by chance in a happy or beneficial way. This word describes finding something good without specifically looking for it.",
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}

#Preview("Error State") {
  WordExplanationSheetContent(
    text: "ephemeral",
    context: "The beauty of cherry blossoms is ephemeral.",
    serviceState: .error("Model not available. Please try again later."),
    translation: "",
    explanation: "",
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}

#Preview("Rich Content") {
  WordExplanationSheetContent(
    text: "ubiquitous",
    context: "Smartphones have become ubiquitous in modern society.",
    serviceState: .success("Success"),
    translation: "どこにでもある、遍在する",
    explanation: """
      **Ubiquitous** means present, appearing, or found everywhere.

      This word is commonly used to describe things that have become so widespread that they seem to be everywhere at once.

      **Examples:**
      - Coffee shops are ubiquitous in urban areas.
      - Wi-Fi has become ubiquitous in public spaces.

      **Origin:** From Latin 'ubique' meaning 'everywhere'.
      """,
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}
