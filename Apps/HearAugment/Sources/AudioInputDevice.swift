import Foundation
@preconcurrency import AVFoundation

struct AudioInputDevice: Identifiable, Hashable {
  let id: String
  let name: String
  let detail: String
  let isBuiltIn: Bool
  let isBluetooth: Bool

  init(port: AVAudioSessionPortDescription) {
    id = port.uid

    name = {
      switch port.portType {
      case .builtInMic:
        return "Device Microphone"
      default:
        return port.portName
      }
    }()

    detail = {
      switch port.portType {
      case .builtInMic:
        return "Built-in input"
      case .bluetoothHFP, .bluetoothLE:
        return "Bluetooth input"
      case .headsetMic:
        return "Headset input"
      case .usbAudio:
        return "USB input"
      case .lineIn:
        return "Line input"
      default:
        return port.portType.rawValue
      }
    }()

    switch port.portType {
    case .builtInMic:
      isBuiltIn = true
      isBluetooth = false
    case .bluetoothHFP, .bluetoothLE:
      isBuiltIn = false
      isBluetooth = true
    default:
      isBuiltIn = false
      isBluetooth = false
    }
  }
}
