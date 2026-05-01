import SwiftUI

/// TimelineViewをラップし、speedパラメータを考慮したphase累積を行う
/// speedを変更しても位相がジャンプせず、滑らかにアニメーションが継続する
struct PhaseTimelineView<Content: View>: View {
  let speed: Float
  @ViewBuilder let content: (_ phase: Double, _ size: CGSize) -> Content

  @State private var phase: Double = 0
  @State private var lastTime: Date?

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation) { context in
        content(phase, geometry.size)
          .onChange(of: context.date) { _, newValue in
            let delta = newValue.timeIntervalSince(lastTime ?? newValue)
            phase += delta * Double(speed)
            lastTime = newValue
          }
          .onAppear {
            lastTime = context.date
          }
      }
    }
    .ignoresSafeArea()
  }
}
