//
//  SelectableSubtitleTextView.swift
//  YouTubeSubtitle
//
//  Created by Claude on 2025/12/10.
//

#if os(iOS)

  import CoreMedia
  import SwiftUI
  import UIKit

// MARK: - RoundedBackgroundLayoutManager

/// Custom NSLayoutManager that draws rounded background rectangles
/// instead of the default rectangular backgrounds.
nonisolated final class RoundedBackgroundLayoutManager: NSLayoutManager {

  /// Corner radius for background highlights
  var cornerRadius: CGFloat = 4

  /// Horizontal padding for the background
  var horizontalPadding: CGFloat = 2

  /// Top padding for the background
  var topPadding: CGFloat = 1

  /// Bottom padding for the background
  var bottomPadding: CGFloat = 0
  
  override func fillBackgroundRectArray(
    _ rectArray: UnsafePointer<CGRect>,
    count rectCount: Int,
    forCharacterRange charRange: NSRange,
    color: UIColor
  ) {
    guard let context = UIGraphicsGetCurrentContext() else {
      super.fillBackgroundRectArray(
        rectArray,
        count: rectCount,
        forCharacterRange: charRange,
        color: color
      )
      return
    }

    // Enable anti-aliasing for smooth rounded corners
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    context.setFillColor(color.cgColor)

    for i in 0..<rectCount {
      var rect = rectArray[i]

      // Add padding around the text (asymmetric top/bottom)
      rect = CGRect(
        x: rect.origin.x - horizontalPadding,
        y: rect.origin.y - topPadding,
        width: rect.width + horizontalPadding * 2,
        height: rect.height + topPadding + bottomPadding
      )

      // Draw rounded rectangle
      let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
      context.addPath(path.cgPath)
      context.fillPath()
    }
  }
}

// MARK: - SelectableSubtitleTextView

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

  /// Corner radius for the highlight background. Set to 0 for sharp corners.
  var highlightCornerRadius: CGFloat

  /// Font to apply to the text.
  var font: UIFont

  /// Text color.
  var textColor: UIColor

  /// Callback when a word is tapped.
  var onWordTap: ((String, CGRect) -> Void)?

  /// Callback when "Explain" is selected from the context menu.
  var onExplain: ((String) -> Void)?

  /// Callback when text selection changes. Returns true if text is selected.
  var onSelectionChanged: ((Bool) -> Void)?

  // MARK: - Initializer

  init(
    text: String,
    wordTimings: [Subtitle.WordTiming]? = nil,
    highlightTime: CMTime? = nil,
    highlightColor: UIColor = UIColor.systemYellow.withAlphaComponent(0.4),
    highlightCornerRadius: CGFloat = 4,
    font: UIFont = .preferredFont(forTextStyle: .body),
    textColor: UIColor = .label,
    onWordTap: ((String, CGRect) -> Void)? = nil,
    onExplain: ((String) -> Void)? = nil,
    onSelectionChanged: ((Bool) -> Void)? = nil
  ) {
    self.text = text
    self.wordTimings = wordTimings
    self.highlightTime = highlightTime
    self.highlightColor = highlightColor
    self.highlightCornerRadius = highlightCornerRadius
    self.font = font
    self.textColor = textColor
    self.onWordTap = onWordTap
    self.onExplain = onExplain
    self.onSelectionChanged = onSelectionChanged
  }

  // MARK: - UIViewRepresentable

  func makeUIView(context: Context) -> UITextView {
    // Create custom text system with rounded background support
    let textStorage = NSTextStorage()
    let layoutManager = RoundedBackgroundLayoutManager()
    layoutManager.cornerRadius = highlightCornerRadius

    let textContainer = NSTextContainer(size: .zero)
    textContainer.widthTracksTextView = true
    textContainer.lineFragmentPadding = 0

    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    // Store layout manager reference in coordinator
    context.coordinator.layoutManager = layoutManager

    let textView = UITextView(frame: .zero, textContainer: textContainer)
    textView.isEditable = false
    textView.isScrollEnabled = false
    textView.backgroundColor = .clear
    // Add inset to prevent highlight background from being clipped
    textView.textContainerInset = UIEdgeInsets(
      top: layoutManager.topPadding,
      left: layoutManager.horizontalPadding,
      bottom: layoutManager.bottomPadding,
      right: layoutManager.horizontalPadding
    )
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

    // Update corner radius if changed
    coordinator.layoutManager?.cornerRadius = highlightCornerRadius

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

    // Reference to custom layout manager for updating corner radius
    weak var layoutManager: RoundedBackgroundLayoutManager?

    // Cache for avoiding unnecessary rebuilds
    var cachedText: String?
    var cachedFont: UIFont?
    var cachedTextColor: UIColor?
    var baseAttributedString: NSAttributedString?
    var wordRanges: [WordRange] = []
    var highlightedRange: NSRange?

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

#endif
