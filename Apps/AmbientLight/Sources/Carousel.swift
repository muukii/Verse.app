import SwiftUI

private struct AnimatableContentMargins: ViewModifier, Animatable {
  var margin: CGFloat

  var animatableData: CGFloat {
    get { margin }
    set { margin = newValue }
  }

  func body(content: Content) -> some View {
    content
      .contentMargins(.horizontal, margin)
  }
}

/**
 Successor of TabView
 */
public struct Carousel<Selection: Hashable, Content: View>: View {

  /// The child views that make up the carousel's items, provided by the view builder.
  private let content: Content

  /// An optional binding to the currently view-aligned item's identifier.
  ///
  /// - When non-nil, programmatic changes scroll to the matching item and user scrolling
  ///   updates the bound selection.
  /// - When nil, the carousel operates unmanaged and does not sync selection.
  private let scrollPosition: Binding<Selection?>?

  /// A Boolean value that determines whether user-driven horizontal scrolling is allowed.
  private let isScrollEnabled: Bool

  /// The spacing, in points, between adjacent items in the horizontal stack.
  private let spacing: CGFloat

  /// The additional horizontal content margin applied to the scroll content.
  ///
  /// This is added to both leading and trailing sides via `.contentMargins(.horizontal, ...)`
  /// so items can be centered/aligned nicely within the available width.
  private let margin: CGFloat

  /// Creates a carousel whose currently aligned item is bound to a selection.
  ///
  /// Use this initializer when you want to programmatically control which item is
  /// scrolled into view and/or observe which item the user has scrolled to. The
  /// selection binding is kept in sync with the currently view-aligned child view,
  /// identified by the value you provide via `.id(_:)` on each child.
  ///
  /// - Important: Each child view in `content` must have a stable identity set with
  ///   `.id(_:)`, and the `id`'s type must match `Selection`. Without IDs, the
  ///   carousel cannot determine which item to align to or update the binding with.
  ///
  /// - Parameters:
  ///   - selection: A binding to the optional identifier of the currently aligned
  ///     item. Setting this to a value will smoothly scroll the carousel to the
  ///     corresponding child view. Setting it to `nil` clears the programmatic
  ///     target; after user interaction, the binding will update to the nearest
  ///     aligned item's ID.
  ///   - isScrollEnabled: A Boolean value that determines whether user scrolling is enabled.
  ///   - spacing: The spacing between adjacent items.
  ///   - margin: Additional horizontal content margin applied to the scroll content.
  ///   - content: A view builder that produces the carousel's items. Each item
  ///     should be tagged with `.id(_:)` using a `Selection` value.
  ///
  /// - Discussion:
  ///   - When `selection` changes, the carousel animates to the matching item using
  ///     a smooth animation.
  ///   - As the user scrolls and alignment settles, the binding updates to reflect
  ///     the currently aligned item's ID.
  ///   - If `selection` does not match any child's ID, no scrolling occurs.
  ///
  /// - Example:
  ///   ```swift
  ///   struct Example: View {
  ///     @State private var selection: String? = "Two"
  ///
  ///     var body: some View {
  ///       Carousel(selection: $selection) {
  ///         Text("One").id("One")
  ///         Text("Two").id("Two")
  ///         Text("Three").id("Three")
  ///       }
  ///     }
  ///   }
  ///   ```
  public init(
    selection: Binding<Selection?>,
    isScrollEnabled: Bool = true,
    spacing: CGFloat = 16,
    margin: CGFloat = 0,
    @ViewBuilder content: () -> Content
  ) {
    self.scrollPosition = selection
    self.isScrollEnabled = isScrollEnabled
    self.spacing = spacing
    self.margin = margin
    self.content = content()
  }

  /// Creates an unmanaged carousel without a bound selection.
  ///
  /// Use this initializer when you don't need to programmatically control or observe
  /// the aligned item. The carousel still supports user scrolling and view alignment.
  ///
  /// - Parameters:
  ///   - isScrollEnabled: A Boolean value that determines whether user scrolling is enabled.
  ///   - spacing: The spacing between adjacent items.
  ///   - margin: Additional horizontal content margin applied to the scroll content.
  ///   - content: A view builder that produces the carousel's items.
  public init(
    isScrollEnabled: Bool = true,
    spacing: CGFloat = 16,
    margin: CGFloat = 0,
    @ViewBuilder content: () -> Content
  ) where Selection == Never {
    self.scrollPosition = nil
    self.isScrollEnabled = isScrollEnabled
    self.spacing = spacing
    self.margin = margin
    self.content = content()
  }

  public var body: some View {
    let view = ScrollView(.horizontal, showsIndicators: false) {
      // In iOS 17, scrollTargetLayout only works if its content is LazyHStack. 🤦
      // @see https://stackoverflow.com/a/77165176
      // For some reason, this worked only for iOS 18+ (iOS 17+ did not scroll at all), so we changed the requirement to iOS 18+.
      //
      // An approach removing UnaryViewReader and ForEach enabled scrolling with iOS 17+, but scrolling behavior was broken in some timings, for all iOS versions 17+.
      // https://github.com/eure/pairs-ios/pull/17957
      // https://eure.slack.com/archives/C30BXT536/p1759974573328599?thread_ts=1759732150.679789&cid=C30BXT536
      // We will continue to find a single solution that works with iOS 17+.
      LazyHStack(spacing: spacing) {
        content
          .containerRelativeFrame(.horizontal)
      }
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.viewAligned)
    .scrollDisabled(!isScrollEnabled)
    .modifier(AnimatableContentMargins(margin: margin))

    if let scrollPosition {
      ScrollViewReader { proxy in
        view
          .animation(
            .smooth,
            body: {
              $0.scrollPosition(id: scrollPosition)
            }
          )
          .onAppear {
            proxy.scrollTo(scrollPosition.wrappedValue)
          }
      }
    } else {
      view
    }
  }

}

#if DEBUG
#Preview("Carousel") {

  @Previewable @State var selection: String?

  VStack {
    HStack {
      Button("One") {
        selection = "One"
      }
      Button("Two") {
        selection = "Two"
      }
      Button("Three") {
        selection = "Three"
      }
      Button("Clear") {
        selection = nil
      }
    }
    Carousel(selection: $selection, margin: 40) {
      Text("One")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.red.opacity(0.3))
        )
        .id("One")
      Text("Two")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.blue.opacity(0.3))
        )
        .id("Two")
      Text("Three")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.green.opacity(0.3))
        )
        .id("Three")
    }
    .padding(.horizontal, 20)
  }
}

#Preview("Carousel default") {

  @Previewable @State var selection: String? = "Two"

  VStack {
    HStack {
      Button("One") {
        selection = "One"
      }
      Button("Two") {
        selection = "Two"
      }
      Button("Three") {
        selection = "Three"
      }
      Button("Clear") {
        selection = nil
      }
    }
    Carousel(selection: $selection) {
      Text("One")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.red.opacity(0.3))
        )
        .id("One")
      Text("Two")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.blue.opacity(0.3))
        )
        .id("Two")
      Text("Three")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.green.opacity(0.3))
        )
        .id("Three")
    }
  }
}

@available(iOS 18, *)
#Preview("Carousel disabled scroll") {

  @Previewable @State var selection: String? = "Two"

  VStack {
    Text("User scroll is disabled")
      .font(.caption)
      .foregroundColor(.secondary)
    Text("Use buttons to navigate")
      .font(.caption2)
      .foregroundColor(.secondary)

    HStack {
      Button("One") {
        selection = "One"
      }
      Button("Two") {
        selection = "Two"
      }
      Button("Three") {
        selection = "Three"
      }
      Button("Clear") {
        selection = nil
      }
    }

    Carousel(selection: $selection, isScrollEnabled: false) {
      Text("One")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.red.opacity(0.3))
        )
        .id("One")
      Text("Two")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.blue.opacity(0.3))
        )
        .id("Two")
      Text("Three")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.green.opacity(0.3))
        )
        .id("Three")
    }
  }
}

#Preview("Carousel margin adjustment") {

  @Previewable @State var selection: String?
  @Previewable @State var margin: CGFloat = 40

  VStack {
    HStack {
      Text("Margin: \(Int(margin))")
        .monospacedDigit()
      Slider(value: $margin, in: 0...120, step: 1)
    }
    .padding(.horizontal)

    HStack {
      Button("One") {
        selection = "One"
      }
      Button("Two") {
        selection = "Two"
      }
      Button("Three") {
        selection = "Three"
      }
    }

    Carousel(selection: $selection, margin: margin) {
      Text("One")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.red.opacity(0.3))
        )
        .id("One")
      Text("Two")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.blue.opacity(0.3))
        )
        .id("Two")
      Text("Three")
        .font(.largeTitle)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.green.opacity(0.3))
        )
        .id("Three")
    }
  }
}

#endif
