//
//  SettingsView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/04.
//

import AppIntents
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        // MARK: - Siri & Shortcuts
        Section {
          SiriTipView(intent: OpenYouTubeVideoIntent())
        } header: {
          Text("Siri")
        } footer: {
          Text("Use Siri to quickly open YouTube videos with subtitles.")
        }

        Section {
          ShortcutsLink()
            .shortcutsLinkStyle(.automaticOutline)
        } header: {
          Text("Shortcuts")
        } footer: {
          Text("Create custom shortcuts with the Shortcuts app.")
        }
      }
      .navigationTitle("Settings")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview {
  SettingsView()
}
