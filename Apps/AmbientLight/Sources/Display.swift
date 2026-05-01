//
//  Display.swift
//  AmbientLight
//
//  Created by Hiroshi Kimura on 2026/02/12.
//

import SwiftUI

struct Display<Content: View, SettingsContent: View>: View {

  let content: Content
  let settingsContent: SettingsContent
  let matrixX: MatrixBinding
  let matrixY: MatrixBinding

  @State private var showsSettings = false
  @State private var isDragging = false
  @State private var showsMatrixControl = false
  @State private var hideTask: Task<Void, Never>?

  private let hideDelay: Double = 1.5

  init(
    matrixX: MatrixBinding,
    matrixY: MatrixBinding,
    @ViewBuilder content: () -> Content,
    @ViewBuilder settingsContent: () -> SettingsContent
  ) {
    self.matrixX = matrixX
    self.matrixY = matrixY
    self.content = content()
    self.settingsContent = settingsContent()
  }

  var body: some View {
    ZStack {
      EdgeGradientMask {
        content
      }
      .allowedDynamicRange(.high)

      controlOverlay
    }
    .contentShape(Rectangle())
    .onTapGesture {
      showsMatrixControl = true
      scheduleHide()
    }
    .onChange(of: isDragging) { _, newValue in
      if newValue {
        // Dragging started - cancel any pending hide
        hideTask?.cancel()
      } else {
        // Dragging ended - schedule hide
        scheduleHide()
      }
    }
    .sensoryFeedback(.impact, trigger: showsMatrixControl)
    .sheet(isPresented: $showsSettings) {
      SettingsView {
        settingsContent
      }
      .presentationDetents([.medium])
    }
  }

  @ViewBuilder
  private var controlOverlay: some View {
    MatrixControl(
      matrixX: matrixX,
      matrixY: matrixY,
      isDragging: $isDragging,
      isVisible: $showsMatrixControl
    )
    .padding(40)
  }

  private func scheduleHide() {
    hideTask?.cancel()
    hideTask = Task {
      do {
        try await Task.sleep(for: .seconds(hideDelay))
        guard !Task.isCancelled else { return }
        await MainActor.run {
          showsMatrixControl = false
        }
      } catch {
        // cancelled
      }
    }
  }

}

struct SettingsView<EmbeddedContent: View>: View {

  @Environment(\.dismiss) private var dismiss

  let embeddedContent: EmbeddedContent

  init(
    @ViewBuilder embeddedContent: () -> EmbeddedContent
  ) {
    self.embeddedContent = embeddedContent()
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          embeddedContent
        } header: {
          Text("Parameters")
        } footer: {
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
