//
//  SelectableSubtitleTextView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/10.
//

import CoreMedia
import SwiftUI
import UIKit

// MARK: - SelectableSubtitleTextView

/// A UITextView-backed SwiftUI view that supports:
/// - Text selection (long-press)
/// - Word tap detection
/// - Time-based highlighting for audio transcription
///
/// Performance optimized: Uses NSMutableAttributedString directly
/// to avoid AttributedString conversion overhead on every update.
struct SelectableSubtitleTextView: UIViewRepresentable {

  // MARK: - Content Enum

  /// Represents the content to display, either plain text or timed words.
  enum Content {
    /// Plain text with cell-level timing for highlight calculation.
    case plainText(text: String, startTime: Double, endTime: Double)
    /// Timed words with per-word timing embedded in WordTiming.
    case timedWords([Subtitle.WordTiming])

    /// Convenience initializer for automatic selection based on wordTimings availability.
    init(text: String, wordTimings: [Subtitle.WordTiming]?, startTime: Double = 0, endTime: Double = 0) {
      if let wordTimings, !wordTimings.isEmpty {
        self = .timedWords(wordTimings)
      } else {
        self = .plainText(text: text, startTime: startTime, endTime: endTime)
      }
    }

    /// The text to display, derived from the content.
    var displayText: String {
      switch self {
      case .plainText(let text, _, _):
        return text
      case .timedWords(let timings):
        return timings.map(\.text).joined(separator: " ")
      }
    }
  }

  // MARK: - Properties

  /// The content to display (plain text or timed words).
  let content: Content

  /// Current playback time for highlighting.
  /// The word containing this time will be highlighted.
  var highlightTime: CMTime?

  /// Font to apply to the text.
  var font: UIFont

  /// Text color.
  var textColor: UIColor

  /// Color for played (past) text in karaoke-style highlighting.
  var playedTextColor: UIColor

  /// Color for unplayed (future) text in karaoke-style highlighting.
  var unplayedTextColor: UIColor

  /// Line spacing between lines of text.
  var lineSpacing: CGFloat

  /// Current playback time in seconds. Used to determine past/future when highlightTime is nil.
  var playbackTime: Double?

  /// Callback when a word is tapped.
  var onWordTap: ((String, CGRect) -> Void)?

  /// Callback when "Explain" is selected from the context menu.
  var onExplain: ((String) -> Void)?

  /// Callback when text selection changes. Returns true if text is selected.
  var onSelectionChanged: ((Bool) -> Void)?

  // MARK: - Initializer

  /// Primary initializer using Content enum.
  init(
    content: Content,
    highlightTime: CMTime? = nil,
    font: UIFont = .preferredFont(forTextStyle: .body),
    textColor: UIColor = .label,
    playedTextColor: UIColor = .label,
    unplayedTextColor: UIColor = .secondaryLabel,
    lineSpacing: CGFloat = 0,
    playbackTime: Double? = nil,
    onWordTap: ((String, CGRect) -> Void)? = nil,
    onExplain: ((String) -> Void)? = nil,
    onSelectionChanged: ((Bool) -> Void)? = nil
  ) {
    self.content = content
    self.highlightTime = highlightTime
    self.font = font
    self.textColor = textColor
    self.playedTextColor = playedTextColor
    self.unplayedTextColor = unplayedTextColor
    self.lineSpacing = lineSpacing
    self.playbackTime = playbackTime
    self.onWordTap = onWordTap
    self.onExplain = onExplain
    self.onSelectionChanged = onSelectionChanged
  }


  // MARK: - UIViewRepresentable

  func makeUIView(context: Context) -> UITextView {
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()

    let textContainer = NSTextContainer(size: .zero)
    textContainer.widthTracksTextView = true
    textContainer.lineFragmentPadding = 0

    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    let textView = UITextView(frame: .zero, textContainer: textContainer)
    textView.isEditable = false
    textView.isScrollEnabled = false
    textView.backgroundColor = .clear
    textView.textContainerInset = UIEdgeInsets(top: 1, left: 2, bottom: 0, right: 2)
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.delegate = context.coordinator

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

    coordinator.onExplain = self.onExplain
    coordinator.onSelectionChanged = self.onSelectionChanged

    // Build word ranges
    let wordRanges = buildWordRanges()

    // Build and apply attributed string
    let displayString = buildAttributedString(wordRanges: wordRanges)

    textView.attributedText = displayString
    textView.invalidateIntrinsicContentSize()
  }

  // MARK: - Private Methods

  /// Builds the complete attributed string with karaoke-style coloring
  private func buildAttributedString(wordRanges: [WordRange]) -> NSAttributedString {
    let displayText = content.displayText

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = lineSpacing

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: textColor,
      .paragraphStyle: paragraphStyle
    ]

    let string = NSMutableAttributedString(string: displayText, attributes: attributes)

    // If no word timings (plain text), apply whole-text coloring based on playbackTime vs startTime
    if wordRanges.isEmpty {
      if let playbackTime, case .plainText(_, let startTime, _) = content {
        let isPastOrCurrentCell = playbackTime >= startTime
        let fullRange = NSRange(location: 0, length: string.length)
        let color = isPastOrCurrentCell ? playedTextColor : unplayedTextColor
        string.addAttribute(.foregroundColor, value: color, range: fullRange)
      }
      return string
    }

    // Find current word index based on highlightTime
    let currentIndex: Int?
    if let highlightTime, highlightTime.isValid {
      let time = highlightTime.seconds
      // Explicitly check if we're before the first word
      if let firstStartTime = wordRanges.first?.startTime, time < firstStartTime {
        currentIndex = nil
      } else {
        currentIndex = binarySearchWord(in: wordRanges, for: time)
      }
    } else {
      currentIndex = nil
    }

    // Find the last word that has been completely played (for gap handling)
    let lastPlayedWordIndex: Int?
    if let playbackTime {
      lastPlayedWordIndex = wordRanges.lastIndex { playbackTime >= $0.endTime }
    } else {
      lastPlayedWordIndex = nil
    }

    // Apply colors to all words based on current position
    for (index, wordRange) in wordRanges.enumerated() {
      guard wordRange.nsRange.location + wordRange.nsRange.length <= string.length else { continue }

      if let current = currentIndex {
        // Current cell with word-level highlighting (within a word's time range)
        if index <= current {
          // Played (past or current word)
          string.addAttribute(.foregroundColor, value: playedTextColor, range: wordRange.nsRange)
        } else {
          // Unplayed (future word)
          string.addAttribute(.foregroundColor, value: unplayedTextColor, range: wordRange.nsRange)
        }
      } else if let lastPlayed = lastPlayedWordIndex, index <= lastPlayed {
        // In a gap between words, but this word has already been played
        string.addAttribute(.foregroundColor, value: playedTextColor, range: wordRange.nsRange)
      } else {
        // Future cell, before first word, or in gap but word not yet played
        string.addAttribute(.foregroundColor, value: unplayedTextColor, range: wordRange.nsRange)
      }
    }

    return string
  }

  /// Builds word ranges for efficient highlight lookup
  private func buildWordRanges() -> [WordRange] {
    guard case .timedWords(let wordTimings) = content else { return [] }

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
    Coordinator(onWordTap: onWordTap, onExplain: onExplain)
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
    var onExplain: ((String) -> Void)?
    var onSelectionChanged: ((Bool) -> Void)?

    // Track previous selection state to avoid redundant callbacks
    private var hadSelection = false

    init(onWordTap: ((String, CGRect) -> Void)?, onExplain: ((String) -> Void)?) {
      self.onWordTap = onWordTap
      self.onExplain = onExplain
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

    // MARK: - UITextViewDelegate

    public func textViewDidChangeSelection(_ textView: UITextView) {
      let hasSelection = textView.selectedRange.length > 0
      // Only notify when selection state actually changes
      if hasSelection != hadSelection {
        hadSelection = hasSelection
        onSelectionChanged?(hasSelection)
      }
    }

    @available(iOS 16.0, *)
    public func textView(
      _ textView: UITextView,
      editMenuForTextIn range: NSRange,
      suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
      guard let onExplain,
            let text = textView.text,
            let swiftRange = Range(range, in: text) else {
        return UIMenu(children: suggestedActions)
      }

      let selectedText = String(text[swiftRange])
      guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return UIMenu(children: suggestedActions)
      }

      let explainAction = UIAction(
        title: "Explain",
        image: UIImage(systemName: "lightbulb")
      ) { _ in
        onExplain(selectedText)
      }

      return UIMenu(children: [explainAction] + suggestedActions)
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 20) {
    SelectableSubtitleTextView(
      content: .plainText(text: "Hello world, this is a test sentence.", startTime: 0, endTime: 5),
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
