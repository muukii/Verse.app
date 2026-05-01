import SwiftUI

struct DeviceHeadroomKey: EnvironmentKey {
  static let defaultValue: Float = 1
}

extension EnvironmentValues {
  var deviceHeadroom: Float {
    get { self[DeviceHeadroomKey.self] }
    set { self[DeviceHeadroomKey.self] = newValue }
  }
}

struct DeviceHeadroomReader<Content: View>: View {
  let content: Content
  @State private var deviceHeadroom: Float = DeviceHeadroomKey.defaultValue

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .environment(\.deviceHeadroom, deviceHeadroom)
      .background {
        DeviceHeadroomReporter(deviceHeadroom: $deviceHeadroom)
          .frame(width: 0, height: 0)
      }
  }
}

private struct DeviceHeadroomReporter: UIViewRepresentable {
  @Binding var deviceHeadroom: Float

  func makeUIView(context: Context) -> HeadroomView {
    let view = HeadroomView()
    view.onHeadroomChange = updateHeadroom(_:)
    return view
  }

  func updateUIView(_ uiView: HeadroomView, context: Context) {
    uiView.onHeadroomChange = updateHeadroom(_:)
    uiView.updateHeadroom()
  }

  private func updateHeadroom(_ value: Float) {
    guard deviceHeadroom != value else { return }

    Task { @MainActor in
      deviceHeadroom = value
    }
  }
}

private final class HeadroomView: UIView {
  var onHeadroomChange: ((Float) -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateHeadroom()
  }

  func updateHeadroom() {
    let screen = window?.windowScene?.screen
    onHeadroomChange?(Float(screen?.currentEDRHeadroom ?? CGFloat(DeviceHeadroomKey.defaultValue)))
  }
}
