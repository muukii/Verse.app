//
//  Mask.swift
//  AmbientLight
//
//  Created by Hiroshi Kimura on 2026/02/13.
//

import SwiftUI

struct EdgeGradientMask<Content: View>: View {

  let content: Content
  @State private var openness: CGFloat = 0

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {

    let minPadding: CGFloat = 80
    let ratio: CGFloat = 1 - openness

    GeometryReader { proxy in
      ZStack {
        content
          .mask {
            Capsule()
              .padding(
                ((proxy.size.width / 2) - minPadding) * ratio + minPadding
              )
              .blur(radius: 30)
          }
      }
    }
    .onAppear {
      open()
    }
  }

  private func open() {
    withAnimation(
      .spring(
        .init(
          mass: 1,
          stiffness: 10,
          damping: 100,
          allowOverDamping: false
        )
      )
    ) {
      openness = 1.0
    }
  }

  private func close() {
    withAnimation(
      .spring(
        .init(
          mass: 1,
          stiffness: 10,
          damping: 100,
          allowOverDamping: false
        )
      )
    ) {
      openness = 0
    }
  }

}

#Preview {
  EdgeGradientMask {
    Color.red
  }
}
