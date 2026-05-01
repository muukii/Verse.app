import SwiftUI

struct ContentView: View {

  @AppStorage("currentPage") private var currentPage: Int = 0
  @State private var isSwitcherMode: Bool = false

  private var margin: CGFloat {
    isSwitcherMode ? 100 : 0
  }

  var body: some View {
    GeometryReader { proxy in

      let windowSize = proxy.size

      ZStack(alignment: .bottom) {
        Carousel(
          selection: .init(get: {
            currentPage
          }, set: { value in
            currentPage = value ?? 0
          }),
          isScrollEnabled: isSwitcherMode,
          margin: margin
        ) {

          Group {
            PatternAmbientFog()
              .id(0)

            PatternAurora()
              .id(1)

            PatternPlasma()
              .id(2)

//            PatternVapor()
//              .id(3)
//
//            PatternGradient()
//              .id(4)

            PatternFire()
              .id(5)

            PatternSmoke()
              .id(6)
          }
          .allowsHitTesting(isSwitcherMode == false)
          .aspectRatio(windowSize, contentMode: .fit)
        }

      }
      .gesture(
        LongPressGesture().onEnded({ _ in
          withAnimation(.spring(duration: 0.3)) {
            isSwitcherMode.toggle()
          }
        })
      )
      .gesture(
        TapGesture().onEnded({ _ in
          withAnimation(.spring(duration: 0.3)) {
            isSwitcherMode = false
          }
        }),
        isEnabled: isSwitcherMode
      )
    }

  }
}

#Preview {
  ContentView()
}
