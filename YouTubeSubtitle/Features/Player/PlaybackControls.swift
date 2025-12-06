//
//  PlaybackControls.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/12/07.
//

import SwiftUI
import SwiftUIRingSlider

// MARK: - PlayerControls

struct PlayerControls: View {
  let model: PlayerModel
  let backwardSeekInterval: Double
  let forwardSeekInterval: Double
  let onSeek: (Double) -> Void
  let onSeekBackward: () -> Void
  let onSeekForward: () -> Void
  let onTogglePlayPause: () -> Void
  let onRateChange: (Double) -> Void
  let onBackwardSeekIntervalChange: (Double) -> Void
  let onForwardSeekIntervalChange: (Double) -> Void
  let onSubtitleSeekBackward: () -> Void
  let onSubtitleSeekForward: () -> Void

  @State private var controlsMode: ControlsMode = .normal

  var body: some View {
    VStack(spacing: 0) {
      ProgressBar(
        currentTime: model.currentTime,
        duration: model.duration,
        onSeek: onSeek
      )
      .padding(.horizontal, 16)
      .padding(.top, 12)

      TimeDisplay(
        currentTime: model.displayTime,
        duration: model.duration
      )
      .padding(.horizontal, 20)
      .padding(.top, 4)

      PlaybackButtonsControl(
        isPlaying: model.isPlaying,
        backwardSeekInterval: backwardSeekInterval,
        forwardSeekInterval: forwardSeekInterval,
        onBackward: onSeekBackward,
        onForward: onSeekForward,
        onTogglePlayPause: onTogglePlayPause,
        onBackwardSeekIntervalChange: onBackwardSeekIntervalChange,
        onForwardSeekIntervalChange: onForwardSeekIntervalChange
      )
      .padding(.top, 8)

      SubtitleSeekControls(
        onBackward: onSubtitleSeekBackward,
        onForward: onSubtitleSeekForward
      )
      .padding(.top, 4)

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
        playbackRate: model.playbackRate,
        onRateChange: onRateChange,
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

// MARK: - ProgressBar

struct ProgressBar: View {
  let currentTime: Double
  let duration: Double
  let onSeek: (Double) -> Void

  var body: some View {
    let normalizedValue = Binding<Double>(
      get: {
        guard duration > 0 else { return 0 }
        return currentTime / duration
      },
      set: { newValue in
        let clampedValue = max(0, min(1, newValue))
        let seekTime = clampedValue * duration
        onSeek(seekTime)
      }
    )

    TouchSlider(
      direction: .horizontal,
      value: normalizedValue,
      speed: 0.5,
      foregroundColor: .red,
      backgroundColor: Color.gray.opacity(0.3)
    )
    .frame(height: 16)
  }
}

// MARK: - TimeDisplay

struct TimeDisplay: View {
  let currentTime: Double
  let duration: Double

  var body: some View {
    HStack {
      Text(formatTime(currentTime))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)

      Spacer()

      Text(formatTime(duration))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }
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
  let isPlaying: Bool
  let backwardSeekInterval: Double
  let forwardSeekInterval: Double
  let onBackward: () -> Void
  let onForward: () -> Void
  let onTogglePlayPause: () -> Void
  let onBackwardSeekIntervalChange: (Double) -> Void
  let onForwardSeekIntervalChange: (Double) -> Void

  private let availableIntervals: [Double] = [3, 5, 10, 15, 30]

  var body: some View {
    HStack(spacing: 32) {
      Button(action: onBackward) {
        seekIcon(direction: .backward, interval: backwardSeekInterval)
      }
      .buttonStyle(.glass)
      .contextMenu {
        seekIntervalMenu(
          currentInterval: backwardSeekInterval,
          onChange: onBackwardSeekIntervalChange
        )
      }

      Button(action: onTogglePlayPause) {
        Image(
          systemName: isPlaying ? "pause.fill" : "play.fill"
        )
        .font(.system(size: 32))
      }
      .buttonStyle(.glass)

      Button(action: onForward) {
        seekIcon(direction: .forward, interval: forwardSeekInterval)
      }
      .buttonStyle(.glass)
      .contextMenu {
        seekIntervalMenu(
          currentInterval: forwardSeekInterval,
          onChange: onForwardSeekIntervalChange
        )
      }
    }
  }

  private enum SeekDirection {
    case backward, forward
  }

  @ViewBuilder
  private func seekIcon(direction: SeekDirection, interval: Double)
    -> some View
  {
    let prefix = direction == .backward ? "gobackward" : "goforward"
    let symbolName: String = {
      switch interval {
      case 5: return "\(prefix).5"
      case 10: return "\(prefix).10"
      case 15: return "\(prefix).15"
      case 30: return "\(prefix).30"
      case 45: return "\(prefix).45"
      case 60: return "\(prefix).60"
      default:
        return prefix
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

  @ViewBuilder
  private func seekIntervalMenu(
    currentInterval: Double,
    onChange: @escaping (Double) -> Void
  ) -> some View {
    ForEach(availableIntervals, id: \.self) { interval in
      Button {
        onChange(interval)
      } label: {
        HStack {
          Text("\(Int(interval)) seconds")
          if interval == currentInterval {
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
      Image(systemName: "speedometer")
        .foregroundStyle(.secondary)
        .font(.system(size: 14))

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
        Text(formatRate(playbackRate))
          .font(.system(.caption, design: .monospaced))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.gray.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
    }
  }

  private func formatRate(_ rate: Double) -> String {
    if rate == 1.0 {
      return "1x"
    } else if rate == floor(rate) {
      return String(format: "%.0fx", rate)
    } else {
      return String(format: "%.2gx", rate)
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
      Image(systemName: model.isLoopingEnabled ? "repeat.circle.fill" : "repeat")
        .font(.system(size: 24))
        .foregroundStyle(model.isLoopingEnabled ? .blue : .secondary)
    }
    .buttonStyle(.plain)
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
      HStack(spacing: 6) {
        Image(systemName: isActive ? "repeat.1.circle.fill" : "repeat.1.circle")
          .font(.system(size: 20))
        Text("A-B")
          .font(.system(.caption, design: .rounded).bold())
      }
      .foregroundStyle(isActive ? .orange : (hasRepeatPoints ? .primary : .secondary))
    }
    .buttonStyle(.plain)
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
          .buttonStyle(.borderedProminent)
          .tint(.blue)
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
        valueRange: 0...max(1, duration)
      )
      .frame(height: 120)

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

// MARK: - NormalModeControls

struct NormalModeControls: View {
  let model: PlayerModel
  let playbackRate: Double
  let onRateChange: (Double) -> Void
  let onEnterRepeatMode: () -> Void

  var body: some View {
    HStack(spacing: 24) {
      SpeedControls(playbackRate: playbackRate, onRateChange: onRateChange)

      Divider().frame(height: 24)

      LoopControl(model: model)

      Divider().frame(height: 24)

      RepeatEntryButton(
        isActive: model.isRepeating,
        hasRepeatPoints: model.repeatStartTime != nil || model.repeatEndTime != nil,
        onTap: onEnterRepeatMode
      )
    }
  }
}

// MARK: - SubtitleSeekControls

struct SubtitleSeekControls: View {
  let onBackward: () -> Void
  let onForward: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text("Subtitle Seek")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        Button(action: onBackward) {
          Image(systemName: "backward.frame.fill")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)

        Button(action: onForward) {
          Image(systemName: "forward.frame.fill")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
      }
    }
  }
}
