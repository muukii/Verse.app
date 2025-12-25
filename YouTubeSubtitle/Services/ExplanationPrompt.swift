//
//  ExplanationPrompt.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/25.
//

import Foundation

/// Shared prompt builder for word/phrase explanations.
/// Used by both on-device LLM (LLMService) and external services (Gemini).
struct ExplanationPrompt {

  // MARK: - Device Language

  /// Returns the device's preferred language name for LLM responses.
  /// For example: "Japanese", "English", "French", etc.
  static var deviceLanguage: String {
    guard let languageCode = Locale.current.language.languageCode?.identifier else {
      return "English"
    }
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

  // MARK: - Prompt Building

  /// Builds the system instruction with language specification.
  /// - Parameter targetLanguage: The language for the response (defaults to device language)
  /// - Returns: Complete system instruction string
  static func buildSystemInstruction(
    customInstruction: String? = nil,
    targetLanguage: String? = nil
  ) -> String {
    let baseInstruction = customInstruction?.isEmpty == false
      ? customInstruction!
      : defaultSystemInstruction
    let language = targetLanguage ?? deviceLanguage
    return "\(baseInstruction)\nRespond in \(language)."
  }

  /// Builds the user prompt with text and context.
  /// - Parameters:
  ///   - text: The word or phrase to explain
  ///   - context: The surrounding context
  ///   - customTemplate: Custom user prompt template (optional)
  /// - Returns: Complete user prompt string
  static func buildUserPrompt(
    text: String,
    context: String,
    customTemplate: String? = nil
  ) -> String {
    let template = customTemplate?.isEmpty == false
      ? customTemplate!
      : defaultUserPromptTemplate

    return template
      .replacingOccurrences(of: "{text}", with: text)
      .replacingOccurrences(of: "{context}", with: context)
  }

  /// Builds the complete prompt (system instruction + user prompt).
  /// - Parameters:
  ///   - text: The word or phrase to explain
  ///   - context: The surrounding context
  ///   - customSystemInstruction: Custom system instruction (optional)
  ///   - customUserPromptTemplate: Custom user prompt template (optional)
  ///   - targetLanguage: The language for the response (defaults to device language)
  /// - Returns: Complete prompt string
  static func buildFullPrompt(
    text: String,
    context: String,
    customSystemInstruction: String? = nil,
    customUserPromptTemplate: String? = nil,
    targetLanguage: String? = nil
  ) -> String {
    let systemInstruction = buildSystemInstruction(
      customInstruction: customSystemInstruction,
      targetLanguage: targetLanguage
    )
    let userPrompt = buildUserPrompt(
      text: text,
      context: context,
      customTemplate: customUserPromptTemplate
    )

    return "\(systemInstruction)\n\n\(userPrompt)"
  }
}
