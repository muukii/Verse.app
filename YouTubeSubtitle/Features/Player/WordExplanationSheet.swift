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

/// Sheet view for displaying LLM-generated word/phrase explanations.
/// This is the stateful container that manages async operations and state.
struct WordExplanationSheet: View {
  let text: String
  let context: String

  @Environment(\.dismiss) private var dismiss
  @State private var service = LLMService()
  @State private var explanationResponse: ExplanationResponse?
  @State private var isLoading: Bool = false
  @State private var errorMessage: String?
  @State private var generationTask: Task<Void, Never>?
  @State private var showsInstructionViewer: Bool = false
  @State private var geminiURL: URL?

  var body: some View {
    WordExplanationSheetContent(
      text: text,
      context: context,
      explanationResponse: explanationResponse,
      isLoading: isLoading,
      errorMessage: errorMessage,
      showsInstructionViewer: $showsInstructionViewer,
      service: service,
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
    generationTask?.cancel()
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
    print("[LLM] Availability: \(availability), preferredBackend: \(service.preferredBackend)")

    guard case .available(let backend) = availability else {
      if case .unavailable(let reason) = availability {
        errorMessage = reason.localizedDescription
      }
      return
    }

    print("[LLM] Using backend: \(backend)")

    isLoading = true
    errorMessage = nil
    explanationResponse = nil

    do {
      let response = try await service.generateExplanation(text: text, context: context)

      // Check for cancellation after receiving response
      guard !Task.isCancelled else {
        isLoading = false
        return
      }

      explanationResponse = response
      print("[LLM] Explanation generated successfully")
    } catch {
      print("[LLM] Explanation error: \(error)")
      // Don't update state if task was cancelled
      guard !Task.isCancelled else { return }
      errorMessage = error.localizedDescription
    }

    isLoading = false
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
  let explanationResponse: ExplanationResponse?
  let isLoading: Bool
  let errorMessage: String?

  // Bindings
  @Binding var showsInstructionViewer: Bool

  // For InstructionViewerSheet
  let service: LLMService

  // Actions
  let onClose: () -> Void
  let onRetry: () -> Void
  let onOpenGemini: () -> Void

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

            Button {
              showsInstructionViewer = true
            } label: {
              Image(systemName: "info.circle")
            }
          }
        }
      }
      .sheet(isPresented: $showsInstructionViewer) {
        InstructionViewerSheet(service: service, text: text, context: context)
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
    VStack(alignment: .leading, spacing: 16) {
      if isLoading {
        loadingView
      } else if let error = errorMessage {
        errorView(message: error)
      } else if let response = explanationResponse {
        structuredExplanationView(response)
      } else {
        placeholderView
      }
    }
  }

  private func structuredExplanationView(_ response: ExplanationResponse) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      // Translation section
      VStack(alignment: .leading, spacing: 4) {
        Label("Translation", systemImage: "character.book.closed")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(response.translation)
          .font(.title3)
          .fontWeight(.medium)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.blue.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .textSelection(.enabled)
      }

      // Explanation section
      VStack(alignment: .leading, spacing: 4) {
        Label("Explanation", systemImage: "sparkles")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(response.explanation)
          .font(.body)
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(.secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .textSelection(.enabled)
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

// MARK: - Instruction Viewer Sheet

/// Sheet view for displaying the composed prompt used in explanation.
private struct InstructionViewerSheet: View {
  let service: LLMService
  let text: String
  let context: String

  @Environment(\.dismiss) private var dismiss

  /// The full composed prompt that will be sent to the LLM
  private var composedPrompt: String {
    ExplanationPrompt.buildFullPrompt(
      text: text,
      context: context,
      customSystemInstruction: service.customSystemInstruction,
      customUserPromptTemplate: service.customUserPromptTemplate
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // MARK: - Composed Prompt
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Label("Composed Prompt", systemImage: "text.alignleft")
                .font(.headline)
              Spacer()
              // Show if using custom settings
              if !service.customSystemInstruction.isEmpty || !service.customUserPromptTemplate.isEmpty {
                Text("Custom")
                  .font(.caption2)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Color.blue.opacity(0.2))
                  .clipShape(Capsule())
                  .foregroundStyle(.blue)
              }
            }

            Text(composedPrompt)
              .font(.system(.caption, design: .monospaced))
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(.secondarySystemBackground))
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .textSelection(.enabled)
          }

          Divider()

          // MARK: - Backend Info
          VStack(alignment: .leading, spacing: 8) {
            Label("Configuration", systemImage: "gearshape")
              .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
              LabeledContent("Backend", value: service.preferredBackend.displayName)
              if service.preferredBackend == .mlx {
                if let model = LLMService.availableMLXModels.first(where: { $0.id == service.selectedMLXModelId }) {
                  LabeledContent("Model", value: model.name)
                }
              }
              LabeledContent("Language", value: ExplanationPrompt.deviceLanguage)
            }
            .font(.callout)
          }
        }
        .padding()
      }
      .navigationTitle("Prompt Details")
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
  WordExplanationSheetContent(
    text: "nevertheless",
    context: "Nevertheless, we decided to proceed with the plan.",
    explanationResponse: nil,
    isLoading: true,
    errorMessage: nil,
    showsInstructionViewer: .constant(false),
    service: LLMService(),
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}

#Preview("With Explanation") {
  WordExplanationSheetContent(
    text: "serendipity",
    context: "It was pure serendipity that we met.",
    explanationResponse: ExplanationResponse(
      translation: "偶然の幸運、思いがけない発見",
      explanation: "Serendipity（セレンディピティ）は、偶然の幸運や思いがけない発見を意味する名詞です。何かを探しているときに、予期せず別の価値あるものを見つけることを表します。この言葉は1754年にホレス・ウォルポールがペルシャの童話「セレンディップの三人の王子」にちなんで作った造語です。"
    ),
    isLoading: false,
    errorMessage: nil,
    showsInstructionViewer: .constant(false),
    service: LLMService(),
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}

#Preview("Error State") {
  WordExplanationSheetContent(
    text: "ephemeral",
    context: "The beauty of cherry blossoms is ephemeral.",
    explanationResponse: nil,
    isLoading: false,
    errorMessage: "Model not available. Please try again later.",
    showsInstructionViewer: .constant(false),
    service: LLMService(),
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}

#Preview("Nevertheless") {
  WordExplanationSheetContent(
    text: "nevertheless",
    context: "Nevertheless, we decided to proceed with the plan.",
    explanationResponse: ExplanationResponse(
      translation: "それにもかかわらず、しかしながら",
      explanation: "Nevertheless（ネバーザレス）は、前述の内容と対照的または矛盾するような文を導入するために使われる副詞です。反対の状況があるにもかかわらず、何かが真実であることを強調します。フォーマルな文章や学術的な文脈でよく使われます。類義語には however、nonetheless、even so、still、yet などがあります。"
    ),
    isLoading: false,
    errorMessage: nil,
    showsInstructionViewer: .constant(false),
    service: LLMService(),
    onClose: {},
    onRetry: {},
    onOpenGemini: {}
  )
}
