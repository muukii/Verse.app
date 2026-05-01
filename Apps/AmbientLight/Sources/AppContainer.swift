//
//  AppContainer.swift
//  AmbientLight
//
//  Created by Hiroshi Kimura on 2026/02/12.
//

import SwiftUI

@Observable
final class AppContainer {

  func enableIdleTimerDisabled() {
    UIApplication.shared.isIdleTimerDisabled = true
  }

  func disableIdleTimerDisabled() {
    UIApplication.shared.isIdleTimerDisabled = false
  }

}
