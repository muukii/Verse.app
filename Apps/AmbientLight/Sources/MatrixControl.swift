import SwiftUI

/// 任意のFloat Bindingをマトリックス軸にバインド
struct MatrixBinding {
  var binding: Binding<Float>
  var range: ClosedRange<Float>

  init(_ binding: Binding<Float>, range: ClosedRange<Float>) {
    self.binding = binding
    self.range = range
  }

  /// -1...1 に正規化された値
  var normalized: CGFloat {
    get {
      let mid = (range.lowerBound + range.upperBound) / 2
      let halfRange = (range.upperBound - range.lowerBound) / 2
      return CGFloat((binding.wrappedValue - mid) / halfRange)
    }
    nonmutating set {
      let mid = (range.lowerBound + range.upperBound) / 2
      let halfRange = (range.upperBound - range.lowerBound) / 2
      binding.wrappedValue = mid + Float(newValue) * halfRange
    }
  }
}

struct MatrixControl: View {

  @Binding var x: CGFloat  // -1.0〜1.0（中央が0）
  @Binding var y: CGFloat  // -1.0〜1.0（中央が0）
  @Binding var isDragging: Bool
  @Binding var isVisible: Bool

  /// MatrixBinding を使った初期化
  init(
    matrixX: MatrixBinding,
    matrixY: MatrixBinding,
    isDragging: Binding<Bool>,
    isVisible: Binding<Bool>
  ) {
    self._x = Binding(
      get: { matrixX.normalized },
      set: { matrixX.normalized = $0 }
    )
    self._y = Binding(
      get: { matrixY.normalized },
      set: { matrixY.normalized = $0 }
    )
    self._isDragging = isDragging
    self._isVisible = isVisible
  }

  /// 直接 x, y を指定する初期化
  init(
    x: Binding<CGFloat>,
    y: Binding<CGFloat>,
    isDragging: Binding<Bool>,
    isVisible: Binding<Bool>
  ) {
    self._x = x
    self._y = y
    self._isDragging = isDragging
    self._isVisible = isVisible
  }

  private let baseDotSize: CGFloat = 4
  private let maxDotSize: CGFloat = 6
  private let influenceRadius: CGFloat = 100

  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      MatrixContentView(
        x: x,
        y: y,
        size: size,
        isVisible: isVisible,
        baseDotSize: baseDotSize,
        maxDotSize: maxDotSize,
        influenceRadius: influenceRadius,
        onDrag: { newX, newY in
          x = newX
          y = newY
        },
        onDragStateChanged: { dragging in
          isDragging = dragging
        }
      )
      .frame(width: size, height: size)
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

private struct MatrixContentView: View, Animatable {
  var x: CGFloat
  var y: CGFloat
  let size: CGFloat
  let isVisible: Bool
  let baseDotSize: CGFloat
  let maxDotSize: CGFloat
  let influenceRadius: CGFloat
  let onDrag: (CGFloat, CGFloat) -> Void
  let onDragStateChanged: (Bool) -> Void

  private let velocityFactor: CGFloat = 0.05
  private let numSteps: Int = 10  // 11 dots = 10 steps
  private let gridPadding: CGFloat = 24

  private func snap(_ value: CGFloat) -> CGFloat {
    let step = 2.0 / CGFloat(numSteps)
    return (round(value / step) * step).clamped(to: -1...1)
  }

  var animatableData: AnimatablePair<CGFloat, CGFloat> {
    get { AnimatablePair(x, y) }
    set {
      x = newValue.first
      y = newValue.second
    }
  }

  private var indicatorPosition: CGPoint {
    let drawableSize = size - gridPadding * 2
    return CGPoint(
      x: gridPadding + (x + 1) / 2 * drawableSize,
      y: gridPadding + (-y + 1) / 2 * drawableSize
    )
  }

  var body: some View {
    let indicatorSize: CGFloat = 24

    ZStack {

      // Dot grid
      DotGridCanvas(
        focusPoint: indicatorPosition,
        baseDotSize: baseDotSize,
        maxDotSize: maxDotSize,
        influenceRadius: influenceRadius,
        padding: gridPadding
      )

      // Position indicator
      Circle()
        .fill(Color.white)
        .frame(width: indicatorSize, height: indicatorSize)
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .position(indicatorPosition)
    }
    .opacity(isVisible ? 1 : 0)
    .animation(.easeInOut(duration: 0.2), value: isVisible)
    .contentShape(Rectangle())
    .allowsHitTesting(isVisible)
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          onDragStateChanged(true)
          let location = value.location
          let drawableSize = size - gridPadding * 2
          let newX = ((location.x - gridPadding) / drawableSize * 2 - 1).clamped(to: -1...1)
          let newY = (1 - (location.y - gridPadding) / drawableSize * 2).clamped(to: -1...1)
          withAnimation(.snappy(duration: 0.2)) {
            onDrag(newX, newY)
          }
        }
        .onEnded { value in
          let drawableSize = size - gridPadding * 2
          // Convert velocity from points/sec to normalized value/sec
          let velocityX = value.velocity.width / drawableSize * 2
          let velocityY = -value.velocity.height / drawableSize * 2

          // Predict final position based on velocity and snap
          let predictedX = snap((x + velocityX * velocityFactor).clamped(to: -1...1))
          let predictedY = snap((y + velocityY * velocityFactor).clamped(to: -1...1))

          withAnimation(.snappy(duration: 0.2)) {
            onDrag(predictedX, predictedY)
          }
          onDragStateChanged(false)
        }
    )
  }
}

private struct DotGridCanvas: View {
  let focusPoint: CGPoint
  let baseDotSize: CGFloat
  let maxDotSize: CGFloat
  let influenceRadius: CGFloat
  let padding: CGFloat

  var body: some View {
    Canvas { context, size in
      let numDots = 11
      let drawableWidth = size.width - padding * 2
      let drawableHeight = size.height - padding * 2
      let spacingX = drawableWidth / CGFloat(numDots - 1)
      let spacingY = drawableHeight / CGFloat(numDots - 1)

      let maxPullDistance: CGFloat = 8  // 最大引き寄せ距離

      for row in 0..<numDots {
        for col in 0..<numDots {
          let gridPosition = CGPoint(
            x: padding + CGFloat(col) * spacingX,
            y: padding + CGFloat(row) * spacingY
          )

          let dx = gridPosition.x - focusPoint.x
          let dy = gridPosition.y - focusPoint.y
          let distance = sqrt(dx * dx + dy * dy)
          let influence = Swift.max(0, 1 - distance / influenceRadius)

          // Gravitational pull towards focus point
          var dotCenter = gridPosition
          if distance > 0 {
            let pullStrength = influence * maxPullDistance
            let directionX = -dx / distance  // normalized direction to focus
            let directionY = -dy / distance
            dotCenter.x += directionX * pullStrength
            dotCenter.y += directionY * pullStrength
          }

          let dotSize = baseDotSize + (maxDotSize - baseDotSize) * influence
          let opacity = 0.2 + 0.6 * influence

          let dotRect = CGRect(
            x: dotCenter.x - dotSize / 2,
            y: dotCenter.y - dotSize / 2,
            width: dotSize,
            height: dotSize
          )

          context.fill(
            Path(ellipseIn: dotRect),
            with: .color(.white.opacity(opacity))
          )
        }
      }
    }
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var x: CGFloat = 0
    @State private var y: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isVisible: Bool = true

    var body: some View {
      VStack(spacing: 20) {
        MatrixControl(x: $x, y: $y, isDragging: $isDragging, isVisible: $isVisible)

        Text("X: \(x, specifier: "%.2f"), Y: \(y, specifier: "%.2f")")
          .font(.caption)
          .foregroundStyle(.white)

        Text(isDragging ? "Dragging" : "Idle")
          .font(.caption)
          .foregroundStyle(isDragging ? .green : .gray)

        Button(isVisible ? "Hide" : "Show") {
          isVisible.toggle()
        }
      }
      .padding()
      .background(Color.black)
    }
  }

  return PreviewWrapper()
}
