//
//  ExplainInstructionSettingsView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/09.
//

import SwiftUI

/// Settings view for customizing the AI explanation instructions.
struct ExplainInstructionSettingsView: View {
  @State private var llmService = LLMService()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      // MARK: - System Instruction
      Section {
        TextEditor(text: llmService.$customSystemInstruction.binding)
          .frame(minHeight: 150)
          .font(.system(.body, design: .monospaced))
      } header: {
        Text("System Instruction")
      } footer: {
        VStack(alignment: .leading, spacing: 8) {
          Text("Defines the AI's role and behavior. Leave empty to use default.")
          Button("Reset to Default") {
            llmService.customSystemInstruction = ""
          }
          .font(.caption)
        }
      }

      // MARK: - Default System Instruction Preview
      Section {
        Text(LLMService.defaultSystemInstruction)
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Default System Instruction")
      }

      // MARK: - User Prompt Template
      Section {
        TextEditor(text: llmService.$customUserPromptTemplate.binding)
          .frame(minHeight: 100)
          .font(.system(.body, design: .monospaced))
      } header: {
        Text("User Prompt Template")
      } footer: {
        VStack(alignment: .leading, spacing: 8) {
          Text("Use {text} and {context} as placeholders. Leave empty to use default.")
          Button("Reset to Default") {
            llmService.customUserPromptTemplate = ""
          }
          .font(.caption)
        }
      }

      // MARK: - Default User Prompt Preview
      Section {
        Text(LLMService.defaultUserPromptTemplate)
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("Default User Prompt Template")
      }

      // MARK: - Placeholders Reference
      Section {
        VStack(alignment: .leading, spacing: 8) {
          PlaceholderRow(placeholder: "{text}", description: "The selected word or phrase")
          PlaceholderRow(placeholder: "{context}", description: "The surrounding subtitle text")
        }
      } header: {
        Text("Available Placeholders")
      }
    }
    .navigationTitle("Explain Instructions")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}

// MARK: - Placeholder Row

private struct PlaceholderRow: View {
  let placeholder: String
  let description: String

  var body: some View {
    HStack {
      Text(placeholder)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.blue)
      Spacer()
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Preview

#Preview {
  NavigationStack {
    ExplainInstructionSettingsView()
  }
}
