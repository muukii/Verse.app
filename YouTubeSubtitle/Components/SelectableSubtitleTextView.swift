//
//  SelectableSubtitleTextView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/10.
//

import CoreMedia
import SwiftUI
import UIKit

/// A UITextView-backed SwiftUI view that supports:
/// - Text selection (long-press)
/// - Word tap detection
/// - Time-based highlighting for audio transcription
///
/// Performance optimized: Uses NSMutableAttributedString directly
/// to avoid AttributedString conversion overhead on every update.
struct SelectableSubtitleTextView: UIViewRepresentable {

  // MARK: - Properties

  /// The plain text to display.
  let text: String

  /// Word-level timing information for highlighting.
  /// If provided, enables time-based word highlighting.
  let wordTimings: [Subtitle.WordTiming]?

  /// Current playback time for highlighting.
  /// The word containing this time will be highlighted.
  var highlightTime: CMTime?

  /// Background color for highlighted text.
  var highlightColor: UIColor

  /// Font to apply to the text.
  var font: UIFont

  /// Text color.
  var textColor: UIColor

  /// Callback when a word is tapped.
  var onWordTap: ((String, CGRect) -> Void)?

  // MARK: - Initializer

  init(
    text: String,
    wordTimings: [Subtitle.WordTiming]? = nil,
    highlightTime: CMTime? = nil,
    highlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.4),
    font: UIFont = .preferredFont(forTextStyle: .body),
    textColor: UIColor = .label,
    onWordTap: ((String, CGRect) -> Void)? = nil
  ) {
    self.text = text
    self.wordTimings = wordTimings
    self.highlightTime = highlightTime
    self.highlightColor = highlightColor
    self.font = font
    self.textColor = textColor
    self.onWordTap = onWordTap
  }

  // MARK: - UIViewRepresentable

  func makeUIView(context: Context) -> UITextView {
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
    for gesture in textView.gestureRecognizers ?? [] {
      if let longPress = gesture as? UILongPressGestureRecognizer {
        tapGesture.require(toFail: longPress)
      }
    }

    textView.addGestureRecognizer(tapGesture)

    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    let coordinator = context.coordinator

    // Check if we need to rebuild the base attributed string
    let needsRebuild = coordinator.cachedText != text
      || coordinator.cachedFont != font
      || coordinator.cachedTextColor != textColor

    if needsRebuild {
      // Build new base attributed string
      let baseString = buildBaseAttributedString()
      coordinator.baseAttributedString = baseString
      coordinator.cachedText = text
      coordinator.cachedFont = font
      coordinator.cachedTextColor = textColor
      coordinator.wordRanges = buildWordRanges()
    }

    // Apply highlight (always, since time changes frequently)
    let displayString: NSAttributedString
    if let baseString = coordinator.baseAttributedString {
      let mutableString = NSMutableAttributedString(attributedString: baseString)
      applyHighlight(to: mutableString, coordinator: coordinator)
      displayString = mutableString
    } else {
      displayString = NSAttributedString(string: text)
    }

    // Only update if content changed
    if textView.attributedText != displayString {
      textView.attributedText = displayString
      textView.invalidateIntrinsicContentSize()
    }
  }

  // MARK: - Private Methods

  /// Builds the base NSAttributedString with font and color (no highlight)
  private func buildBaseAttributedString() -> NSAttributedString {
    let displayText: String
    if let wordTimings, !wordTimings.isEmpty {
      // Reconstruct text from word timings with spaces
      displayText = wordTimings.map(\.text).joined(separator: " ")
    } else {
      displayText = text
    }

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor
    ]

    return NSAttributedString(string: displayText, attributes: attributes)
  }

  /// Builds word ranges for efficient highlight lookup
  private func buildWordRanges() -> [WordRange] {
    guard let wordTimings, !wordTimings.isEmpty else { return [] }

    var ranges: [WordRange] = []
    var currentLocation = 0

    for timing in wordTimings {
      let length = timing.text.count
      let range = NSRange(location: currentLocation, length: length)
      ranges.append(WordRange(
        nsRange: range,
        startTime: timing.startTime,
        endTime: timing.endTime
      ))
      // Add 1 for space between words
      currentLocation += length + 1
    }

    return ranges
  }

  /// Apply highlight to the word at the current time using binary search
  private func applyHighlight(to string: NSMutableAttributedString, coordinator: Coordinator) {
    guard let highlightTime, highlightTime.isValid else { return }

    let time = highlightTime.seconds
    let wordRanges = coordinator.wordRanges

    // Clear previous highlight if exists
    if let previousRange = coordinator.highlightedRange {
      string.removeAttribute(.backgroundColor, range: previousRange)
      coordinator.highlightedRange = nil
    }

    // Binary search for the word containing the current time
    guard let index = binarySearchWord(in: wordRanges, for: time) else { return }

    let wordRange = wordRanges[index]

    // Verify range is valid
    guard wordRange.nsRange.location + wordRange.nsRange.length <= string.length else { return }

    // Apply highlight
    string.addAttribute(.backgroundColor, value: highlightColor, range: wordRange.nsRange)
    coordinator.highlightedRange = wordRange.nsRange
  }

  /// Binary search to find the word containing the given time
  private func binarySearchWord(in ranges: [WordRange], for time: Double) -> Int? {
    guard !ranges.isEmpty else { return nil }

    var low = 0
    var high = ranges.count - 1

    while low <= high {
      let mid = (low + high) / 2
      let range = ranges[mid]

      if time >= range.startTime && time < range.endTime {
        return mid
      } else if time < range.startTime {
        high = mid - 1
      } else {
        low = mid + 1
      }
    }

    return nil
  }

  @MainActor
  public func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView textView: UITextView,
    context: Context
  ) -> CGSize? {
    let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
    let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: size.height)
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(onWordTap: onWordTap)
  }

  // MARK: - WordRange

  struct WordRange {
    let nsRange: NSRange
    let startTime: Double
    let endTime: Double
  }

  // MARK: - Coordinator

  public class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    var onWordTap: ((String, CGRect) -> Void)?

    // Cache for avoiding unnecessary rebuilds
    var cachedText: String?
    var cachedFont: UIFont?
    var cachedTextColor: UIColor?
    var baseAttributedString: NSAttributedString?
    var wordRanges: [WordRange] = []
    var highlightedRange: NSRange?

    init(onWordTap: ((String, CGRect) -> Void)?) {
      self.onWordTap = onWordTap
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      guard let textView = gesture.view as? UITextView else { return }
      let point = gesture.location(in: textView)

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
      text: "Hello world, this is a test sentence.",
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
