//
//  WordDetailSheet.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/27.
//

import SwiftUI
import Translation

/// A sheet displaying word details with translate, explain, and copy actions.
struct WordDetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  let word: String

  @State private var showTranslation = false
  @State private var showExplanation = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text(word)
          .font(.largeTitle)
          .fontWeight(.bold)
          .padding(.top, 40)

        Text("Tapped word")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Spacer()

        VStack(spacing: 12) {
          // Translate button
          Button {
            showTranslation = true
          } label: {
            Label("Translate", systemImage: "translate")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          // Explain button
          Button {
            showExplanation = true
          } label: {
            Label("Explain", systemImage: "sparkles")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)

          // Copy button
          Button {
            UIPasteboard.general.string = word
          } label: {
            Label("Copy to Clipboard", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.bottom, 40)
      }
      .navigationTitle("Word Detail")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium])
    .translationPresentation(
      isPresented: $showTranslation,
      text: word
    )
    .sheet(isPresented: $showExplanation) {
      WordExplanationSheet(
        text: word,
        context: word
      )
    }
  }
}

#Preview {
  WordDetailSheet(word: "Hello")
}
