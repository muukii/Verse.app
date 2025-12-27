//
//  VocabularyEditSheet.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/10.
//

import SwiftUI

struct VocabularyEditSheet: View {
  enum Mode: Identifiable {
    case add
    case edit(VocabularyItem)

    var id: String {
      switch self {
      case .add: return "add"
      case .edit(let item): return item.id.uuidString
      }
    }

    var isEditing: Bool {
      if case .edit = self { return true }
      return false
    }
  }

  let mode: Mode

  @Environment(\.dismiss) private var dismiss
  @Environment(VocabularyService.self) private var vocabularyService

  @State private var llmService = LLMService()

  @State private var term: String = ""
  @State private var meaning: String = ""
  @State private var context: String = ""
  @State private var notes: String = ""
  @State private var showDeleteConfirmation: Bool = false

  // Auto-fill state
  @State private var isAutoFilling: Bool = false
  @State private var autoFillError: String?

  private var title: String {
    mode.isEditing ? "Edit Term" : "Add Term"
  }

  private var canSave: Bool {
    !term.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        // Term (required) with auto-fill button
        Section {
          HStack {
            TextField("Word or phrase", text: $term)
              .textInputAutocapitalization(.never)

            Button {
              Task {
                await performAutoFill()
              }
            } label: {
              if isAutoFilling {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: "sparkles")
              }
            }
            .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty || isAutoFilling)
            .buttonStyle(.borderless)
          }
        } header: {
          Text("Term")
        } footer: {
          if let error = autoFillError {
            Text(error)
              .foregroundStyle(.red)
          } else {
            Text("Tap ✨ to auto-fill fields using AI")
          }
        }

        // Meaning
        Section {
          TextField("Definition or translation", text: $meaning, axis: .vertical)
            .lineLimit(3...6)
        } header: {
          Text("Meaning")
        }

        // Context
        Section {
          TextField("Example sentence", text: $context, axis: .vertical)
            .lineLimit(2...4)
        } header: {
          Text("Context")
        } footer: {
          Text("The sentence where you found this term")
        }

        // Notes
        Section {
          TextField("Your notes", text: $notes, axis: .vertical)
            .lineLimit(2...4)
        } header: {
          Text("Notes")
        }

        // Delete (edit mode only)
        if case .edit(let item) = mode {
          Section {
            Button(role: .destructive) {
              showDeleteConfirmation = true
            } label: {
              HStack {
                Spacer()
                Text("Delete Term")
                Spacer()
              }
            }
          }
          .confirmationDialog(
            "Delete \"\(item.term)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
          ) {
            Button("Delete", role: .destructive) {
              try? vocabularyService.deleteItem(item)
              dismiss()
            }
          } message: {
            Text("This action cannot be undone.")
          }
        }
      }
      .navigationTitle(title)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            save()
          }
          .disabled(!canSave)
        }
      }
      .onAppear {
        loadInitialValues()
      }
    }
    .presentationDetents([.medium, .large])
  }

  // MARK: - Actions

  private func loadInitialValues() {
    if case .edit(let item) = mode {
      term = item.term
      meaning = item.meaning ?? ""
      context = item.context ?? ""
      notes = item.notes ?? ""
    }
  }

  private func save() {
    let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
    guard !trimmedTerm.isEmpty else { return }

    let trimmedMeaning = meaning.isEmpty ? nil : meaning
    let trimmedContext = context.isEmpty ? nil : context
    let trimmedNotes = notes.isEmpty ? nil : notes

    switch mode {
    case .add:
      try? vocabularyService.addItem(
        term: trimmedTerm,
        meaning: trimmedMeaning,
        context: trimmedContext,
        notes: trimmedNotes,
        duplicateHandling: .allowDuplicate
      )

    case .edit(let item):
      try? vocabularyService.updateItem(
        item,
        term: trimmedTerm,
        meaning: trimmedMeaning,
        context: trimmedContext,
        notes: trimmedNotes
      )
    }

    dismiss()
  }

  private func performAutoFill() async {
    let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
    guard !trimmedTerm.isEmpty else { return }

    isAutoFilling = true
    autoFillError = nil

    do {
      let response = try await llmService.generateVocabularyAutoFill(
        term: trimmedTerm,
        context: context.isEmpty ? nil : context
      )

      // Only fill empty fields to preserve user input
      if meaning.isEmpty {
        meaning = response.meaning
      }
      if context.isEmpty {
        context = response.exampleSentence
      }
      if notes.isEmpty {
        notes = response.notes
      }
    } catch {
      autoFillError = error.localizedDescription
    }

    isAutoFilling = false
  }
}

// MARK: - Preview

#Preview("Add") {
  VocabularyEditSheet(mode: .add)
}
