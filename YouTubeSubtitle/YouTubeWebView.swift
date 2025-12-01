//
//  YouTubeWebView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/01.
//

import SwiftUI
import WebKit

struct YouTubeWebView: View {
  let onOpenPlayer: (String) -> Void

  @State private var webView: WKWebView?
  @State private var currentURL: URL?

  private var isVideoPage: Bool {
    guard let url = currentURL else { return false }
    let path = url.path
    return path.hasPrefix("/watch") || path.hasPrefix("/shorts/")
  }

  private var detectedVideoID: String? {
    guard let url = currentURL, isVideoPage else { return nil }
    return YouTubeURLParser.extractVideoID(from: url)
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      YouTubeWebViewRepresentable(
        onURLChanged: { url in
          currentURL = url
        },
        webViewRef: $webView
      )

      // Show button when video is detected
      if let videoID = detectedVideoID, let url = currentURL {
        Button {
          onOpenPlayer(videoID)
        } label: {
          VStack(spacing: 4) {
            Label("Open with Subtitles", systemImage: "captions.bubble")
              .font(.headline)
            Text(url.absoluteString)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: detectedVideoID)
      }
    }
    #if os(iOS)
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        Button {
          webView?.goBack()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(webView?.canGoBack != true)

        Button {
          webView?.goForward()
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(webView?.canGoForward != true)

        Spacer()

        Button {
          webView?.reload()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    #else
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        Button {
          webView?.goBack()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(webView?.canGoBack != true)

        Button {
          webView?.goForward()
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(webView?.canGoForward != true)

        Button {
          webView?.reload()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    #endif
  }
}

#if os(iOS)
private struct YouTubeWebViewRepresentable: UIViewRepresentable {
  let onURLChanged: (URL?) -> Void
  @Binding var webViewRef: WKWebView?

  func makeCoordinator() -> Coordinator {
    Coordinator(onURLChanged: onURLChanged)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    context.coordinator.observeURL(of: webView)

    // Load YouTube mobile
    if let url = URL(string: "https://m.youtube.com") {
      webView.load(URLRequest(url: url))
    }

    DispatchQueue.main.async {
      webViewRef = webView
    }

    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}
}
#else
private struct YouTubeWebViewRepresentable: NSViewRepresentable {
  let onURLChanged: (URL?) -> Void
  @Binding var webViewRef: WKWebView?

  func makeCoordinator() -> Coordinator {
    Coordinator(onURLChanged: onURLChanged)
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    context.coordinator.observeURL(of: webView)

    // Load YouTube
    if let url = URL(string: "https://www.youtube.com") {
      webView.load(URLRequest(url: url))
    }

    DispatchQueue.main.async {
      webViewRef = webView
    }

    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

private class Coordinator: NSObject, WKNavigationDelegate {
  let onURLChanged: (URL?) -> Void
  private var urlObservation: NSKeyValueObservation?

  init(onURLChanged: @escaping (URL?) -> Void) {
    self.onURLChanged = onURLChanged
  }

  func observeURL(of webView: WKWebView) {
    urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
      DispatchQueue.main.async {
        self?.onURLChanged(webView.url)
      }
    }
  }
}

#Preview {
  NavigationStack {
    YouTubeWebView { videoID in
      print("Open player for: \(videoID)")
    }
  }
}
