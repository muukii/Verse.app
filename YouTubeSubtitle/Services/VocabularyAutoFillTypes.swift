//
//  VocabularyAutoFillTypes.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/27.
//

import FoundationModels

// MARK: - Vocabulary Auto-Fill Response (FoundationModels native)

/// Structured response for vocabulary term auto-fill feature.
/// Uses FoundationModels' @Generable for native structured generation with Apple Intelligence.
/// This file is separate to avoid type ambiguity with AnyLanguageModel's types.
@Generable
struct VocabularyAutoFillResponse: Sendable {
  @Guide(description: "The meaning or definition of the term")
  var meaning: String

  @Guide(description: "An example sentence using the term")
  var exampleSentence: String

  @Guide(description: "Additional notes about usage, nuances, or etymology")
  var notes: String
}
