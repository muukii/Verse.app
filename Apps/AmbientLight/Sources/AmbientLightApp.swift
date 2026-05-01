//
//  AmbientLightApp.swift
//  AmbientLight
//
//  Created by Hiroshi Kimura on 2026/02/09.
//

import SwiftUI

@main
struct AmbientLightApp: App {

  let container = AppContainer()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .tint(Color(red: 0.98, green: 0.69, blue: 0.36))
        .statusBarHidden()
    }
    .environment(container)
    .onChange(of: scenePhase) { oldPhase, newPhase in
      switch newPhase {
      case .active:
        container.enableIdleTimerDisabled()
      case .inactive, .background:
        container.disableIdleTimerDisabled()
      @unknown default:
        break
      }
    }
  }

}

private struct RootView: View {

  var body: some View {
    DeviceHeadroomReader {
      ContentView()
        .background(.black)
    }
  }
}
