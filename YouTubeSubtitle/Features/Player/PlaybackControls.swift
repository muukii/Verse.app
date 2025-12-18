//
//  PlaybackControls.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/07.
//

import SwiftUI
import SwiftUIRingSlider
import Components

// MARK: - PlayerControls

struct PlayerControls: View {
  @Bindable var model: PlayerModel

  @State private var controlsMode: ControlsMode = .normal

  var body: some View {
    VStack(spacing: 0) {
      ProgressSection(
        currentTime: model.currentTime,
        displayTime: model.displayTime,
        duration: model.duration,
        onSeek: { model.seek(to: $0) }
      )
      .padding(.horizontal, 20)
      .padding(.top, 12)

      PlaybackButtonsControl(model: model)
        .padding(.top, 8)

      bottomControlsSection
        .padding(.top, 8)
        .padding(.bottom, 16)
        .animation(.smooth(duration: 0.3), value: controlsMode)
    }
  }

  @ViewBuilder
  private var bottomControlsSection: some View {
    switch controlsMode {
    case .normal:
      NormalModeControls(
        model: model,
        onEnterRepeatMode: { controlsMode = .repeatSetup }
      )
      .transition(.opacity.combined(with: .scale(scale: 0.95)))

    case .repeatSetup:
      RepeatSetupControls(
        model: model,
        onDone: { controlsMode = .normal }
      )
      .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
  }
}

extension PlayerControls {
  
  // MARK: - ProgressSection

  struct ProgressSection: View {
    let currentTime: CurrentTime
    let displayTime: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
      VStack(spacing: 4) {
        progressBar
        timeDisplay
      }
    }

    private var progressBar: some View {
      let normalizedValue = Binding<Double>(
        get: {
          guard duration > 0 else { return 0 }
          return currentTime.value / duration
        },
        set: { newValue in
          let clampedValue = max(0, min(1, newValue))
          let seekTime = clampedValue * duration
          onSeek(seekTime)
        }
      )

      return TouchSlider(
        direction: .horizontal,
        value: normalizedValue,
        speed: 0.5,
        foregroundColor: .red,
        backgroundColor: Color.gray.opacity(0.3)
      )
      .frame(height: 16)
    }

    private var timeDisplay: some View {
      HStack {
        Text(formatTime(displayTime))
          .font(.system(.caption, design: .default).monospacedDigit())
          .foregroundStyle(.secondary)

        Spacer()

        Text(formatTime(duration))
          .font(.system(.caption, design: .default).monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 4)
    }

    private func formatTime(_ seconds: Double) -> String {
      let totalSeconds = Int(seconds)
      let hours = totalSeconds / 3600
      let minutes = (totalSeconds % 3600) / 60
      let secs = totalSeconds % 60

      if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
      } else {
        return String(format: "%d:%02d", minutes, secs)
      }
    }
  }
  
  // MARK: - PlaybackButtonsControl

  struct PlaybackButtonsControl: View {
    @Bindable var model: PlayerModel

    @AppStorage("backwardSeekMode") private var backwardSeekMode: SeekMode = .seconds3
    @AppStorage("forwardSeekMode") private var forwardSeekMode: SeekMode = .seconds3

    var body: some View {
      ZStack {
        SpeedControls(
          playbackRate: model.playbackRate,
          onRateChange: { model.setPlaybackRate($0) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)

        LoopControl(model: model)
          .frame(maxWidth: .infinity, alignment: .trailing)

        HStack(spacing: 32) {
          Button { model.backward(how: backwardSeekMode) } label: {
            seekIcon(direction: .backward, mode: backwardSeekMode)
          }
          .contextMenu {
            seekModeMenu(
              currentMode: backwardSeekMode,
              onChange: { backwardSeekMode = $0 }
            )
          }

          Button { model.togglePlayPause() } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 32))
          }

          Button { model.forward(how: forwardSeekMode) } label: {
            seekIcon(direction: .forward, mode: forwardSeekMode)
          }
          .contextMenu {
            seekModeMenu(
              currentMode: forwardSeekMode,
              onChange: { forwardSeekMode = $0 }
            )
          }
        }
        .tint(Color.primary)
      }
      .padding(.horizontal, 20)
    }

    private enum SeekDirection {
      case backward, forward
    }

    @ViewBuilder
    private func seekIcon(direction: SeekDirection, mode: SeekMode) -> some View {
      if mode.isSubtitleBased {
        // Subtitle-based icon
        let symbolName = direction == .backward ? "backward.frame.fill" : "forward.frame.fill"
        Image(systemName: symbolName)
          .font(.system(size: 24))
          .foregroundStyle(.primary)
      } else {
        // Time-based icon
        let prefix = direction == .backward ? "gobackward" : "goforward"
        let interval = mode.interval ?? 3
        let symbolName: String = {
          switch Int(interval) {
          case 5: return "\(prefix).5"
          case 10: return "\(prefix).10"
          case 15: return "\(prefix).15"
          case 30: return "\(prefix).30"
          case 45: return "\(prefix).45"
          case 60: return "\(prefix).60"
          default: return prefix
          }
        }()

        if interval == 3 || ![5, 10, 15, 30, 45, 60].contains(Int(interval)) {
          // Custom view for 3 seconds or other non-standard intervals
          ZStack {
            Image(systemName: prefix)
              .font(.system(size: 24))
            Text("\(Int(interval))")
              .font(.system(size: 8, weight: .bold))
              .offset(y: 1)
          }
          .foregroundStyle(.primary)
        } else {
          Image(systemName: symbolName)
            .font(.system(size: 24))
            .foregroundStyle(.primary)
        }
      }
    }

    @ViewBuilder
    private func seekModeMenu(
      currentMode: SeekMode,
      onChange: @escaping (SeekMode) -> Void
    ) -> some View {
      ForEach(SeekMode.allCases, id: \.self) { mode in
        Button {
          onChange(mode)
        } label: {
          HStack {
            Text(mode.displayName)
            if mode == currentMode {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    }
  }
  
  // MARK: - SpeedControls
  
  struct SpeedControls: View {
    let playbackRate: Double
    let onRateChange: (Double) -> Void
    
    private let availableRates: [Double] = [
      0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0,
    ]
    
    var body: some View {
      HStack(spacing: 8) {
        
        Menu {
          ForEach(availableRates, id: \.self) { rate in
            Button {
              onRateChange(rate)
            } label: {
              HStack {
                Text(formatRate(rate))
                if rate == playbackRate {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: -8) {
            Text("\(formatRate(playbackRate))")
              .font(.system(size: 17, weight: .bold, design: .rounded))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
            
            Text(Image.init(systemName: "multiply"))
              .font(.system(size: 11, weight: .bold, design: .rounded))
          }
          .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
      }
    }
    
    private func formatRate(_ rate: Double) -> String {
      if rate == 1.0 {
        return "1"
      } else if rate == floor(rate) {
        return String(format: "%.0f", rate)
      } else {
        return String(format: "%.2g", rate)
      }
    }
  }
  
  // MARK: - LoopControl
  
  struct LoopControl: View {
    let model: PlayerModel
    
    var body: some View {
      Button {
        model.toggleLoop()
      } label: {
        Image(systemName: "repeat")
          .font(.system(size: 24))
      }
      .buttonStyle(ToggleButtonStyle(isOn: model.isLoopingEnabled))

    }
  }
  
  // MARK: - ControlsMode
  
  enum ControlsMode {
    case normal
    case repeatSetup
  }
  
  // MARK: - RepeatEntryButton
  
  struct RepeatEntryButton: View {
    let isActive: Bool
    let hasRepeatPoints: Bool
    let onTap: () -> Void
    
    var body: some View {
      Button(action: onTap) {
        Image(systemName: "point.forward.to.point.capsulepath.fill")
      }
    }
  }
  
  // MARK: - RepeatSetupControls
  
  struct RepeatSetupControls: View {
    let model: PlayerModel
    let onDone: () -> Void
    
    @State private var startValue: Double = 0
    @State private var endValue: Double = 0
    
    var body: some View {
      VStack(spacing: 12) {
        // Header row
        HStack {
          Text("Set A-B Repeat")
            .font(.headline)
          Spacer()
          Button("Done", action: onDone)
        }
        
        // A-B RingSlider row
        HStack(spacing: 24) {
          RingSliderPointControl(
            labelImage: Image(systemName: "chevron.left.to.line"),
            value: $startValue,
            duration: model.duration,
            onSetToCurrent: { model.setRepeatStartToCurrent() },
            currentButtonImage: Image.init(systemName: "diamond.lefthalf.filled")
          )
          
          RingSliderPointControl(
            labelImage: Image(systemName: "chevron.right.to.line"),
            value: $endValue,
            duration: model.duration,
            onSetToCurrent: { model.setRepeatEndToCurrent() },
            currentButtonImage: Image.init(systemName: "diamond.righthalf.filled")
          )
        }
        
        // Actions row
        HStack(spacing: 16) {
          if model.repeatStartTime != nil || model.repeatEndTime != nil {
            Button {
              model.clearRepeat()
            } label: {
              Label("Clear", systemImage: "xmark.circle")
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
          }
          
          Spacer()
          
          if model.isRepeating {
            Button {
              model.toggleRepeat()
            } label: {
              Label("Repeating", systemImage: "repeat.circle.fill")
                .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
          } else {
            Button {
              model.toggleRepeat()
            } label: {
              Label("Start Repeat", systemImage: "repeat.circle")
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canToggleRepeat)
          }
        }
      }
      .padding(.horizontal, 16)
      .onAppear {
        // Initialize with model values or defaults
        startValue = model.repeatStartTime ?? 0
        endValue = model.repeatEndTime ?? model.duration
      }
      .onChange(of: startValue) { _, newValue in
        model.repeatStartTime = newValue
      }
      .onChange(of: endValue) { _, newValue in
        model.repeatEndTime = newValue
      }
      .onChange(of: model.repeatStartTime) { _, newValue in
        if let value = newValue, value != startValue {
          startValue = value
        }
      }
      .onChange(of: model.repeatEndTime) { _, newValue in
        if let value = newValue, value != endValue {
          endValue = value
        }
      }
    }
    
    
    // MARK: - RingSliderPointControl
    
    struct RingSliderPointControl: View {
      let labelImage: Image
      @Binding var value: Double
      let duration: Double
      let onSetToCurrent: () -> Void
      let currentButtonImage: Image
      
      var body: some View {
        VStack(spacing: 8) {
          
          labelImage
          
          Text(formatTime(value))
            .font(.system(.caption, design: .rounded, weight: .medium))
          
          RingSlider(
            value: $value,
            stride: 0.25,
            valueRange: 0...max(1, duration),
            primaryTickMark: {
              RoundedRectangle(cornerRadius: 8)
                .frame(width: 2)
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
            },
            secondaryTickMark: {
              RoundedRectangle(cornerRadius: 8)
                .frame(width: 2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 15)
            }
          )
          .frame(height: 60)
          .foregroundStyle(.primary)
          
          Button {
            onSetToCurrent()
          } label: {
            currentButtonImage
          }
          .tint(.secondary)
          .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
      }
      
      private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        let millis = Int((seconds - Double(totalSeconds)) * 1000)
        
        if hours > 0 {
          return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, millis)
        } else {
          return String(format: "%d:%02d.%03d", minutes, secs, millis)
        }
      }
    }
    
  }
  
  // MARK: - NormalModeControls
  
  struct NormalModeControls: View {
    let model: PlayerModel
    let onEnterRepeatMode: () -> Void

    var body: some View {
      HStack(spacing: 24) {
      

        Divider().frame(height: 24)

        RepeatEntryButton(
          isActive: model.isRepeating,
          hasRepeatPoints: model.repeatStartTime != nil || model.repeatEndTime != nil,
          onTap: onEnterRepeatMode
        )
      }
    }
  }
  
}

#if DEBUG

import SwiftData
#Preview {
  let container = try! ModelContainer(
    for: VideoItem.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
  )
  let downloadManager = DownloadManager(modelContainer: container)
  let historyService = VideoHistoryService(
    modelContext: container.mainContext,
    downloadManager: downloadManager
  )

  let item = VideoItem(
    videoID: "oRc4sndVaWo",
    url: "https://www.youtube.com/watch?v=oRc4sndVaWo",
    title: "Preview Video"
  )

  return NavigationStack {
    PlayerView(videoItem: item)
  }
  .modelContainer(container)
  .environment(downloadManager)
  .environment(historyService)
}

#endif
