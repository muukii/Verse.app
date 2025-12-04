//
//  URLInputSheet.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/04.
//

import SwiftUI

struct URLInputSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var urlText: String = ""
  @FocusState private var isTextFieldFocused: Bool

  let onSubmit: (String) -> Void

  var body: some View {

    VStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text("YouTube URL")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        HStack(spacing: 8) {
          Image(systemName: "link")
            .foregroundStyle(.secondary)
            .font(.system(size: 16, weight: .medium))

          TextField("Paste YouTube URL", text: $urlText)
            .textContentType(.URL)
            #if os(iOS)
              .keyboardType(.URL)
              .autocapitalization(.none)
            #endif
            .focused($isTextFieldFocused)
            .onSubmit {
              submitURL()
            }

          if !urlText.isEmpty {
            Button {
              urlText = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }

      Button {
        submitURL()
      } label: {
        Text("Open Video")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!isValidURL)

      Spacer()
    }
    .padding(20)
    .navigationTitle("Enter URL")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      //      .onAppear {
      //        isTextFieldFocused = true
      //      }
    }
  }

  private var isValidURL: Bool {
    guard let url = URL(string: urlText), !urlText.isEmpty else {
      return false
    }
    return YouTubeURLParser.extractVideoID(from: url) != nil
  }

  private func submitURL() {
    guard isValidURL else { return }
    onSubmit(urlText)
    dismiss()
  }
}

#Preview {
  URLInputSheet { url in
    print("URL: \(url)")
  }
}
