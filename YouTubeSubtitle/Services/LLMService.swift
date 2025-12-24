//
//  LLMService.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/05.
//

import AnyLanguageModelMLX  // Re-exports AnyLanguageModel with MLX trait enabled
import StateGraph
import SwiftUI

// MARK: - MLX Model Definition

struct MLXModel: Identifiable, Hashable {
  let id: String
  let name: String
  let size: String
}

// MARK: - LLM Service

/// Service for generating word/phrase explanations using on-device LLM.
/// Uses AnyLanguageModel for unified API with both Apple Intelligence and MLX backends.
@MainActor
@Observable
final class LLMService {

  // MARK: - Device Language

  /// Returns the device's preferred language name for LLM responses.
  /// For example: "Japanese", "English", "French", etc.
  static var deviceLanguage: String {
    guard let languageCode = Locale.current.language.languageCode?.identifier else {
      return "English"
    }
    // Get the language name in English (e.g., "Japanese", "French")
    return Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English"
  }

  // MARK: - Default Instructions

  static let defaultSystemInstruction = """
    You are a language assistant that supports English learning.
    Users select words or phrases from video subtitles to ask questions.

    ## Input Format
    - "Selected": The word/phrase the user wants explained
    - "Context": The surrounding subtitle context where the word/phrase appears

    ## Output Rules

    ### 1. For Words (1-2 words)
    Respond in the following format:
    - **Part of Speech**: noun/verb/adjective/adverb, etc.
    - **Pronunciation**: Phonetic notation
    - **Meaning**: Translation based on context
    - **Usage in Context**: How it is used in this specific subtitle
    - **Example Sentence**: One practical example sentence (with translation)

    ### 2. For Phrases/Idioms (3+ words, or idiomatic expressions)
    Respond in the following format:
    - **Type**: idiom/phrasal verb/collocation/fixed expression, etc.
    - **Meaning**: Explanation of the meaning
    - **Usage in Context**: How it is used in this specific subtitle
    - **Nuance**: Formal/casual, usage situations, etc.
    - **Example Sentence**: One practical example sentence (with translation)

    ### 3. For Full Sentences/Longer Text
    Respond in the following format:
    - **Sentence Structure**: Explanation of subject, verb, object structure
    - **Translation**: Natural translation
    - **Key Points**: Notable grammatical points or difficult parts

    Keep your response concise, including only necessary information.
    """

  static let defaultUserPromptTemplate = """
    Selected: "{text}"

    Context:
    {context}

    Please explain "{text}" in the context of the above subtitles.
    """

  // MARK: - Types

  enum State: Equatable {
    case idle
    case loading
    case downloadingModel(progress: Double)
    case success(String)
    case error(String)
  }

  enum Backend: Equatable, CaseIterable, Identifiable {
    case appleIntelligence
    case mlx

    var id: String {
      switch self {
      case .appleIntelligence: return "appleIntelligence"
      case .mlx: return "mlx"
      }
    }

    var displayName: String {
      switch self {
      case .appleIntelligence: return "Apple Intelligence"
      case .mlx: return "Local Model (MLX)"
      }
    }

    static var allCases: [Backend] {
      [.appleIntelligence, .mlx]
    }
  }

  enum Availability {
    case available(backend: Backend)
    case unavailable(reason: UnavailabilityReason)

    enum UnavailabilityReason {
      case deviceNotEligible
      case appleIntelligenceNotEnabled
      case modelNotReady
      case mlxModelNotLoaded
      case unknown(String)

      nonisolated var localizedDescription: String {
        switch self {
        case .deviceNotEligible:
          return "This device does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
          return "Please enable Apple Intelligence in Settings."
        case .modelNotReady:
          return "The language model is being downloaded. Please try again later."
        case .mlxModelNotLoaded:
          return "MLX model is not loaded. Please download a model first."
        case .unknown(let description):
          return description
        }
      }
    }
  }

  // MARK: - Properties

  var state: State = .idle
  var currentBackend: Backend?

  /// User's preferred backend (persisted in UserDefaults)
  var preferredBackend: Backend = {
    let stored = UserDefaults.standard.string(forKey: "LLMService.preferredBackend")
    switch stored {
    case "mlx": return .mlx
    default: return .appleIntelligence
    }
  }() {
    didSet {
      UserDefaults.standard.set(preferredBackend.id, forKey: "LLMService.preferredBackend")
    }
  }

  /// Available MLX models
  static let availableMLXModels: [MLXModel] = [
    MLXModel(
      id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
      name: "Qwen 2.5 1.5B",
      size: "~900MB"
    ),
    MLXModel(
      id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
      name: "Qwen 2.5 3B",
      size: "~1.8GB"
    ),
    MLXModel(
      id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
      name: "Llama 3.2 1B",
      size: "~700MB"
    ),
    MLXModel(
      id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
      name: "Llama 3.2 3B",
      size: "~1.8GB"
    ),
    MLXModel(
      id: "mlx-community/gemma-3-1b-it-4bit",
      name: "Gemma 3 1B",
      size: "~600MB"
    ),
    MLXModel(
      id: "mlx-community/gemma-3-4b-it-4bit",
      name: "Gemma 3 4B",
      size: "~2.5GB"
    ),
  ]

  /// Selected MLX model ID (persisted in UserDefaults)
  var selectedMLXModelId: String = {
    UserDefaults.standard.string(forKey: "LLMService.selectedMLXModelId")
      ?? availableMLXModels.first!.id
  }() {
    didSet {
      UserDefaults.standard.set(selectedMLXModelId, forKey: "LLMService.selectedMLXModelId")
    }
  }

  /// AnyLanguageModel session (shared for both Apple Intelligence and MLX)
  private var anyLMSession: AnyLanguageModel.LanguageModelSession?

  /// Current generation task (for cancellation support)
  /// Using nonisolated(unsafe) because Task.cancel() is thread-safe and we need to
  /// access this from AsyncThrowingStream's builder closure.
  nonisolated(unsafe) private var currentGenerationTask: Task<Void, Never>?

  // MARK: - Custom Instructions (UserDefaults backed)

  /// Custom system instruction (empty = use default)
  @GraphStored(backed: .userDefaults(key: "LLMService.customSystemInstruction"))
  @ObservationIgnored
  var customSystemInstruction: String = ""

  /// Custom user prompt template (empty = use default)
  @GraphStored(backed: .userDefaults(key: "LLMService.customUserPromptTemplate"))
  @ObservationIgnored
  var customUserPromptTemplate: String = ""

  /// Effective system instruction (custom if set, otherwise default)
  var effectiveSystemInstruction: String {
    customSystemInstruction.isEmpty ? Self.defaultSystemInstruction : customSystemInstruction
  }

  /// Effective user prompt template (custom if set, otherwise default)
  var effectiveUserPromptTemplate: String {
    customUserPromptTemplate.isEmpty ? Self.defaultUserPromptTemplate : customUserPromptTemplate
  }

  // MARK: - Public Methods

  /// Check if any LLM backend is available based on user preference.
  func checkAvailability() -> Availability {
    switch preferredBackend {
    case .mlx:
      // MLX is always available (model downloads on first use)
      return .available(backend: .mlx)

    case .appleIntelligence:
      let appleModel = AnyLanguageModel.SystemLanguageModel.default
      if appleModel.isAvailable {
        return .available(backend: .appleIntelligence)
      }
      // Fall back to MLX if Apple Intelligence not available
      return .available(backend: .mlx)
    }
  }

  /// Check Apple Intelligence availability specifically
  func checkAppleIntelligenceAvailability() -> Availability {
    let model = AnyLanguageModel.SystemLanguageModel.default
    return mapAppleUnavailabilityReason(model.availability)
  }

  private func mapAppleUnavailabilityReason<R>(
    _ availability: AnyLanguageModel.Availability<R>
  ) -> Availability {
    switch availability {
    case .available:
      return .available(backend: .appleIntelligence)
    case .unavailable(let reason):
      // Map the reason based on string representation since UnavailableReason is generic
      let reasonString = String(describing: reason)
      if reasonString.contains("deviceNotEligible") {
        return .unavailable(reason: .deviceNotEligible)
      } else if reasonString.contains("appleIntelligenceNotEnabled") {
        return .unavailable(reason: .appleIntelligenceNotEnabled)
      } else if reasonString.contains("modelNotReady") {
        return .unavailable(reason: .modelNotReady)
      } else {
        return .unavailable(reason: .unknown(reasonString))
      }
    }
  }

  // MARK: - Text Generation

  /// Generate an explanation for a word or phrase within its context.
  func explain(
    text: String,
    context: String,
    targetLanguage: String? = nil
  ) async throws -> String {
    let resolvedLanguage = targetLanguage ?? Self.deviceLanguage
    let availability = checkAvailability()

    switch availability {
    case .available(let backend):
      let model = makeModel(for: backend)
      return try await generateExplanation(
        model: model,
        backend: backend,
        text: text,
        context: context,
        targetLanguage: resolvedLanguage
      )

    case .unavailable(let reason):
      state = .error(reason.localizedDescription)
      throw LLMError.notAvailable(reason)
    }
  }

  /// Stream an explanation for a word or phrase.
  func streamExplanation(
    text: String,
    context: String,
    targetLanguage: String? = nil
  ) -> AsyncThrowingStream<String, any Error> {
    let resolvedLanguage = targetLanguage ?? Self.deviceLanguage
    let availability = checkAvailability()

    switch availability {
    case .available(let backend):
      let model = makeModel(for: backend)
      return streamExplanation(
        model: model,
        backend: backend,
        text: text,
        context: context,
        targetLanguage: resolvedLanguage
      )

    case .unavailable(let reason):
      return AsyncThrowingStream { continuation in
        continuation.finish(throwing: LLMError.notAvailable(reason))
      }
    }
  }

  /// Reset the service state.
  func reset() {
    cancelCurrentGeneration()
    state = .idle
    anyLMSession = nil
  }

  /// Cancel any ongoing generation.
  /// Call this when the sheet is dismissed to stop LLM generation.
  func cancelCurrentGeneration() {
    currentGenerationTask?.cancel()
    currentGenerationTask = nil
  }

  // MARK: - Unified Generation Implementation

  /// Create the appropriate model for the given backend.
  private func makeModel(for backend: Backend) -> any AnyLanguageModel.LanguageModel {
    switch backend {
    case .appleIntelligence:
      return AnyLanguageModel.SystemLanguageModel.default
    case .mlx:
      return AnyLanguageModel.MLXLanguageModel(modelId: selectedMLXModelId)
    }
  }

  /// Generate explanation using any LanguageModel backend.
  private func generateExplanation(
    model: any AnyLanguageModel.LanguageModel,
    backend: Backend,
    text: String,
    context: String,
    targetLanguage: String
  ) async throws -> String {
    state = .loading
    currentBackend = backend

    do {
      let instructions = buildInstructions(targetLanguage: targetLanguage)
      let session = AnyLanguageModel.LanguageModelSession(
        model: model,
        instructions: instructions
      )
      self.anyLMSession = session

      let prompt = buildPrompt(text: text, context: context)
      let response = try await session.respond(to: AnyLanguageModel.Prompt(prompt))
      let explanation = response.content

      state = .success(explanation)
      return explanation

    } catch let error as AnyLanguageModel.LanguageModelSession.GenerationError {
      let errorMessage = handleGenerationError(error)
      state = .error(errorMessage)
      throw LLMError.generationFailed(errorMessage)

    } catch {
      let errorMessage = String(describing: error)
      state = .error(errorMessage)
      throw LLMError.unknown(error)
    }
  }

  /// Stream explanation using any LanguageModel backend.
  /// Note: MLX backend's streamResponse() is a stub, so we use respond() instead.
  private func streamExplanation(
    model: any AnyLanguageModel.LanguageModel,
    backend: Backend,
    text: String,
    context: String,
    targetLanguage: String
  ) -> AsyncThrowingStream<String, any Error> {
    // Cancel any previous generation before starting a new one
    currentGenerationTask?.cancel()

    return AsyncThrowingStream { continuation in
      let task = Task { @MainActor in
        do {
          // Check for cancellation before starting
          try Task.checkCancellation()

          print("[LLMService] Starting with backend: \(backend)")
          self.state = .loading
          self.currentBackend = backend

          let instructions = self.buildInstructions(targetLanguage: targetLanguage)
          print("[LLMService] Creating session...")
          let session = AnyLanguageModel.LanguageModelSession(
            model: model,
            instructions: instructions
          )
          self.anyLMSession = session

          let prompt = self.buildPrompt(text: text, context: context)

          // MLX's streamResponse() is a stub that returns empty immediately
          // Use respond() for MLX backend instead
          if backend == .mlx {
            print("[LLMService] Using respond() for MLX backend...")

            // Check for cancellation before long-running operation
            try Task.checkCancellation()

            let response = try await session.respond(to: AnyLanguageModel.Prompt(prompt))

            // Check for cancellation after receiving response
            try Task.checkCancellation()

            let content = response.content
            print("[LLMService] MLX response: \(content.prefix(100))...")
            continuation.yield(content)
            self.state = .success(content)
            continuation.finish()
          } else {
            // Apple Intelligence supports streaming
            print("[LLMService] Using streamResponse() for Apple Intelligence...")
            var fullContent = ""

            for try await snapshot in session.streamResponse(to: AnyLanguageModel.Prompt(prompt)) {
              // Check for cancellation on each chunk
              try Task.checkCancellation()

              if let stringContent = snapshot.content as? String {
                fullContent = stringContent
              } else {
                fullContent = snapshot.rawContent.jsonString
              }
              continuation.yield(fullContent)
            }

            print("[LLMService] Stream finished successfully")
            self.state = .success(fullContent)
            continuation.finish()
          }

        } catch is CancellationError {
          print("[LLMService] Generation cancelled")
          // Don't set error state when cancelled - this is intentional
          continuation.finish()

        } catch let error as AnyLanguageModel.LanguageModelSession.GenerationError {
          print("[LLMService] GenerationError: \(error)")
          let errorMessage = self.handleGenerationError(error)
          self.state = .error(errorMessage)
          continuation.finish(throwing: LLMError.generationFailed(errorMessage))

        } catch {
          print("[LLMService] Unknown error: \(error)")
          let errorMessage = String(describing: error)
          self.state = .error(errorMessage)
          continuation.finish(throwing: LLMError.unknown(error))
        }
      }

      // Store the task for cancellation support
      self.currentGenerationTask = task

      // Handle stream termination (e.g., when consumer stops iterating)
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  // MARK: - Shared Helpers

  private func buildInstructions(targetLanguage: String) -> String {
    let baseInstruction = effectiveSystemInstruction
    return "\(baseInstruction)\nRespond in \(targetLanguage)."
  }

  private func buildPrompt(text: String, context: String) -> String {
    effectiveUserPromptTemplate
      .replacingOccurrences(of: "{text}", with: text)
      .replacingOccurrences(of: "{context}", with: context)
  }

  private func handleGenerationError(
    _ error: AnyLanguageModel.LanguageModelSession.GenerationError
  ) -> String {
    switch error {
    case .exceededContextWindowSize:
      return "The text is too long to process. Please try with a shorter selection."
    case .refusal(let refusal, _):
      // Extract explanation from refusal if available
      return "Unable to generate explanation: \(refusal)"
    case .assetsUnavailable:
      return "Language model assets are not available. Please try again later."
    case .guardrailViolation:
      return "The content violates safety guidelines."
    case .unsupportedGuide:
      return "The generation guide is not supported."
    case .unsupportedLanguageOrLocale:
      return "The language or locale is not supported."
    case .decodingFailure:
      return "Failed to decode the response."
    case .rateLimited:
      return "Rate limited. Please try again later."
    case .concurrentRequests:
      return "Too many concurrent requests. Please try again."
    }
  }
}

// MARK: - LLM Error

enum LLMError: LocalizedError {
  case notAvailable(LLMService.Availability.UnavailabilityReason)
  case generationFailed(String)
  case mlxModelLoadFailed(any Error)
  case unknown(any Error)

  var errorDescription: String? {
    switch self {
    case .notAvailable(let reason):
      return reason.localizedDescription
    case .generationFailed(let message):
      return message
    case .mlxModelLoadFailed(let error):
      return "Failed to load MLX model: \(error.localizedDescription)"
    case .unknown(let error):
      return String(describing: error)
    }
  }
}

// MARK: - Preview Support

extension LLMService {
  /// Create a mock service for previews
  static func preview(state: State = .idle) -> LLMService {
    let service = LLMService()
    service.state = state
    return service
  }
}
