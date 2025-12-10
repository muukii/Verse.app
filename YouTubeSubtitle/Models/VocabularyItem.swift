//
//  VocabularyItem.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/10.
//

import Foundation
import SwiftData
import TypedIdentifier

// MARK: - Vocabulary Item

/// Represents a vocabulary item (saved word/phrase/expression) for language learning.
/// Independent of videos - vocabulary items are managed as a standalone collection.
@Model
final class VocabularyItem: TypedIdentifiable {

  typealias TypedIdentifierRawValue = UUID

  var typedID: TypedIdentifier<VocabularyItem> {
    .init(id)
  }

  // MARK: - Core Properties

  var id: UUID

  /// The term (word, phrase, or expression) being saved
  var term: String

  /// The meaning/definition (user-provided or LLM-generated)
  var meaning: String?

  /// The context sentence where the term appeared (from subtitle)
  var context: String?

  /// User-added notes
  var notes: String?

  /// Timestamp when the item was created
  var createdAt: Date

  /// Timestamp when the item was last updated
  var updatedAt: Date

  // MARK: - Internal Storage

  /// Lowercase term for case-insensitive duplicate checking (SwiftData optimization)
  internal var _termLowercase: String

  /// Learning state stored as String (SwiftData optimization)
  internal var _learningState: String

  /// Review count for spaced repetition
  var reviewCount: Int

  /// Next review date (for spaced repetition)
  var nextReviewDate: Date?

  // MARK: - Learning State Enum

  enum LearningState: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case reviewing
    case mastered
  }

  var learningState: LearningState {
    get { LearningState(rawValue: _learningState) ?? .new }
    set { _learningState = newValue.rawValue }
  }

  // MARK: - Initialization

  init(
    term: String,
    meaning: String? = nil,
    context: String? = nil,
    notes: String? = nil
  ) {
    self.id = UUID()
    self.term = term
    self._termLowercase = term.lowercased().trimmingCharacters(in: .whitespaces)
    self.meaning = meaning
    self.context = context
    self.notes = notes
    self.createdAt = Date()
    self.updatedAt = Date()
    self._learningState = LearningState.new.rawValue
    self.reviewCount = 0
    self.nextReviewDate = nil
  }

  // MARK: - Update Helpers

  /// Updates the term and its lowercase index
  func updateTerm(_ newTerm: String) {
    self.term = newTerm
    self._termLowercase = newTerm.lowercased().trimmingCharacters(in: .whitespaces)
    self.updatedAt = Date()
  }
}
