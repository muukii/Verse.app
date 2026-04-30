import SwiftUI
import AppService
import StateGraph

struct SettingsView: View {
  
  // @StateObject var manager = ActivityManager.shared
  
  let service: Service
  
  var body: some View {
    NavigationStack {
      Form {
//        Section("OpenAI API") {
//          SecureField("API Key", text: service.$openAIAPIKey.binding)
//            .textContentType(.password)
//        }
        
        Section("Background Processing") {
          Toggle("Background Transcription Notifications", isOn: service.$backgroundTranscriptionNotificationsEnabled.binding)
          Text("Receive a notification when transcription completes in the background")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        
        Section("Display") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Subtitle Font Size")
            HStack {
              Text("12pt")
                .font(.caption)
                .foregroundStyle(.secondary)
              Slider(value: service.$chunkFontSize.binding, in: 12...48, step: 1)
              Text("48pt")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text("Current: \(Int(service.chunkFontSize))pt")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        // Section {
        //   Button("Start") {
        //     manager.startActivity()
        //   }
        //   Button("Stop") {
        //     manager.stopActivity()
        //   }
        // }

      }
      .navigationTitle("Settings")
    }
  }
}

import ActivityKit
import ToneActivityContent

// @MainActor
// final class ActivityManager: ObservableObject {
//   
//   static let shared = ActivityManager()
//   
//   private var currentActivity: Activity<MyActivityAttributes>?
//   
//   private init() {
//     
//   }
//   
//   func startActivity() {
//     do {
//       
//       let state = MyActivityAttributes.ContentState(text: "Hello!")
//       
//       let r = try Activity.request(
//         attributes: MyActivityAttributes(),
//         content: .init(state: state, staleDate: nil),
//         pushType: nil
//       )
//       
//       self.currentActivity = r
//     } catch {
//       print(error)
//     }
//   }
//   
//   func stopActivity(isolation: (any Actor)? = #isolation) {
//     Task { @MainActor [currentActivity] in
//       await currentActivity?.end(nil)
//     }
//   }
//       
// }

#Preview {
  SettingsView(service: Service())
}
