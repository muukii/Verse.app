//
//  SelectionActionSheet.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/01/03.
//

import SwiftUI
import UIKit

/// A bottom sheet that provides actions for selected text.
/// Displays the selected text at the top and offers actions like Explain, Copy, and Add to Vocabulary.
/// Manages its own child sheet state internally - sheets stack naturally.
struct SelectionActionSheet: View {
  let selectedText: String
  /// Optional context for LLM explanation (e.g., surrounding subtitle text). Defaults to selectedText if nil.
  var context: String? = nil
  let onCopy: () -> Void
  let onDismiss: () -> Void

  // Internal state for child sheets - stacking approach
  @State private var showExplanation = false
  @State private var showVocabulary = false

  /// The context to use for explanation - falls back to selectedText if not provided
  private var explanationContext: String {
    context ?? selectedText
  }

  var body: some View {
    VStack(spacing: 16) {
      // Handle indicator
      Capsule()
        .fill(Color(.systemGray4))
        .frame(width: 36, height: 5)
        .padding(.top, 8)

      // Selected text display
      VStack(alignment: .leading, spacing: 4) {
        Text("Selected Text")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(selectedText)
          .font(.body)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(Color(.secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .padding(.horizontal)

      // Action buttons
      VStack(spacing: 12) {
        // Primary action row
        HStack(spacing: 12) {
          Button {
            showExplanation = true
          } label: {
            Label("Explain", systemImage: "sparkles")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          Button {
            showVocabulary = true
          } label: {
            Label("Vocabulary", systemImage: "plus.circle")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }

        // Secondary action row
        Button {
          UIPasteboard.general.string = selectedText
          onCopy()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
      .padding(.horizontal)

      Spacer()
    }
    .presentationDetents([.height(260)])
    .presentationDragIndicator(.hidden)
    .sheet(isPresented: $showExplanation) {
      WordExplanationSheet(text: selectedText, context: explanationContext)
    }
    .sheet(isPresented: $showVocabulary) {
      VocabularyEditSheet(mode: .add(initialTerm: selectedText))
    }
  }
}

// MARK: - Preview

#Preview {
  Text("Preview")
    .sheet(isPresented: .constant(true)) {
      SelectionActionSheet(
        selectedText: "This is a sample selected text that might be quite long and wrap to multiple lines.",
        onCopy: { print("Copy tapped") },
        onDismiss: { print("Dismiss tapped") }
      )
    }
}
