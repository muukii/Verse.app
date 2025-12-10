//
//  SelectableSubtitleTextView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/10.
//

import CoreMedia
import Speech
import SwiftUI
import UIKit

/// A UITextView-backed SwiftUI view that supports:
/// - Text selection (long-press)
/// - Word tap detection
/// - Time-based highlighting for audio transcription
///
/// Usage:
/// ```swift
/// SelectableSubtitleTextView(
///   attributedText: transcription.text,
///   highlightTimeRange: currentPlaybackRange,
///   onWordTap: { word, rect in
///     // Handle word tap
///   }
/// )
/// ```
public struct SelectableSubtitleTextView: UIViewRepresentable {

  // MARK: - Properties

  /// The attributed string to display.
  /// Supports `audioTimeRange` attributes from SpeechTranscriber.
  public let attributedText: AttributedString

  /// Optional time range to highlight.
  /// Text with matching `audioTimeRange` attributes will be highlighted.
  public var highlightTimeRange: CMTimeRange?

  /// Background color for highlighted text.
  public var highlightColor: UIColor

  /// Font to apply to the text. Defaults to `.body` text style.
  public var font: UIFont

  /// Text color. Defaults to `.label`.
  public var textColor: UIColor

  /// Callback when a word is tapped.
  /// - Parameters:
  ///   - word: The tapped word string
  ///   - rect: The bounding rect of the word in the text view's coordinate space
  public var onWordTap: ((String, CGRect) -> Void)?

  // MARK: - Initializer

  public init(
    attributedText: AttributedString,
    highlightTimeRange: CMTimeRange? = nil,
    highlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.4),
    font: UIFont = .preferredFont(forTextStyle: .body),
    textColor: UIColor = .label,
    onWordTap: ((String, CGRect) -> Void)? = nil
  ) {
    self.attributedText = attributedText
    self.highlightTimeRange = highlightTimeRange
    self.highlightColor = highlightColor
    self.font = font
    self.textColor = textColor
    self.onWordTap = onWordTap
  }

  // MARK: - UIViewRepresentable

  public func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.isEditable = false
    textView.isScrollEnabled = false
    textView.backgroundColor = .clear
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Single tap gesture for word detection
    let tapGesture = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap(_:))
    )
    tapGesture.delegate = context.coordinator

    // Make tap gesture require long press gestures to fail first
    // This prevents tap from firing when user is trying to select text
    for gesture in textView.gestureRecognizers ?? [] {
      if let longPress = gesture as? UILongPressGestureRecognizer {
        tapGesture.require(toFail: longPress)
      }
    }

    textView.addGestureRecognizer(tapGesture)

    return textView
  }

  public func updateUIView(_ textView: UITextView, context: Context) {
    // Create a mutable copy of the attributed string
    var styledText = attributedText

    // Apply font and color to the entire string
    if styledText.startIndex < styledText.endIndex {
      let fullRange = styledText.startIndex..<styledText.endIndex
      styledText[fullRange].font = font
      styledText[fullRange].foregroundColor = textColor

      // Apply highlight if timeRange is specified
      if let timeRange = highlightTimeRange {
        // Manually find and highlight words that intersect with the time range
        applyHighlight(to: &styledText, for: timeRange)
      }
    }

    textView.attributedText = NSAttributedString(styledText)

    // Invalidate intrinsic content size to trigger re-layout
    textView.invalidateIntrinsicContentSize()
  }

  /// Manually applies highlight to characters whose audioTimeRange intersects with the given time range.
  private func applyHighlight(to text: inout AttributedString, for timeRange: CMTimeRange) {
    var index = text.startIndex
    while index < text.endIndex {
      // Get the run at this index
      let run = text.runs[index]

      // Check if this run has an audioTimeRange attribute
      if let wordTimeRange = run.audioTimeRange {
        // Check if the word's time range intersects with the highlight time range
        // For point-in-time highlighting, we check if the time is within the word's range
        let highlightTime = timeRange.start
        if wordTimeRange.containsTime(highlightTime) {
          // Apply highlight to this run's range
          text[run.range].backgroundColor = highlightColor
        }
      }

      // Move to the next run
      index = run.range.upperBound
    }
  }

  @MainActor
  public func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView textView: UITextView,
    context: Context
  ) -> CGSize? {
    let width = proposal.width ?? UIView.layoutFittingExpandedSize.width

    // Calculate the size that fits the content
    let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))

    return CGSize(width: width, height: size.height)
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(onWordTap: onWordTap)
  }

  // MARK: - Coordinator

  public class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var onWordTap: ((String, CGRect) -> Void)?

    init(onWordTap: ((String, CGRect) -> Void)?) {
      self.onWordTap = onWordTap
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let textView = gesture.view as? UITextView else { return }
      let point = gesture.location(in: textView)

      // Get tapped word using tokenizer
      if let position = textView.closestPosition(to: point),
        let range = textView.tokenizer.rangeEnclosingPosition(
          position, with: .word, inDirection: UITextDirection.storage(.forward)
        )
      {
        let word = textView.text(in: range) ?? ""
        if !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          let rect = textView.firstRect(for: range)
          onWordTap?(word, rect)
        }
      }
    }

    // Allow tap gesture to work alongside text selection
    public func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 20) {
    SelectableSubtitleTextView(
      attributedText: AttributedString("Hello world, this is a test sentence."),
      onWordTap: { word, _ in
        print("Tapped: \(word)")
      }
    )
    .padding()
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
  .padding()
}
