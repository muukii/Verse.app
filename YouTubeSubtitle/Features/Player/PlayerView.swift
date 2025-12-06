//
//  PlayerView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import AVKit
import ObjectEdge
import SwiftData
import SwiftSubtitles
import SwiftUI
import SwiftUIRingSlider
import YouTubeKit
import YouTubePlayerKit
import YoutubeTranscript
import Translation

struct PlayerView: View {
  let videoItem: VideoItem

  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(DownloadManager.self) private var downloadManager
  @Environment(VideoHistoryService.self) private var historyService
  @ObjectEdge private var model = PlayerModel()

  @State private var playerController: PlayerController?
  @State private var trackingTask: Task<Void, Never>?
  @State private var currentSubtitles: Subtitles?
  @State private var isLoadingTranscripts: Bool = false
  @State private var transcriptError: String?
  @AppStorage("backwardSeekInterval") private var backwardSeekInterval: Double = 3
  @AppStorage("forwardSeekInterval") private var forwardSeekInterval: Double = 3
  @State private var subtitleSource: SubtitleSource = .youtube
  @State private var showDownloadView: Bool = false
  @State private var playbackSource: PlaybackSource = .youtube
  @State private var localFileURL: URL?

  @State private var height: CGFloat = 0
  @State private var isPlayerCollapsed: Bool = false

  // Transcription state
  @State private var isTranscribing: Bool = false
  @State private var transcriptionState: TranscriptionService.TranscriptionState = .idle
  @State private var showTranscriptionSheet: Bool = false

  // Subtitle interaction state
  @State private var selectedCueForExplanation: Subtitles.Cue?
  @State private var selectedCueForTranslation: Subtitles.Cue?

  // Computed property to access videoID from the entity
  private var videoID: YouTubeContentID { videoItem.videoID }

  var body: some View {
    if let controller = playerController {

      ZStack {
        
        VStack {        
          VideoPlayerSection(controller: controller)
            .compositingGroup()
            .animation(.smooth) {              
              $0.opacity(isPlayerCollapsed ? 0 : 1)
                .scaleEffect(isPlayerCollapsed ? 0.95 : 1, anchor: .center)              
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
              self.height = newValue
            }                  
        }
        .frame(maxHeight: .infinity, alignment: .top)

        VStack {
          
          Color.clear
            .animation(.smooth) {              
              $0
                .frame(height: isPlayerCollapsed ? 0 : height)
            }
          
          VStack {
            // Player collapse toggle button
            Button {
              withAnimation(.smooth) {
                isPlayerCollapsed.toggle()
              }
            } label: {
              HStack(spacing: 6) {
                Image(systemName: isPlayerCollapsed ? "chevron.down" : "chevron.up")
                  .font(.system(size: 12, weight: .semibold))
                Text(isPlayerCollapsed ? "Show Player" : "Hide Player")
                  .font(.caption)
              }
              .foregroundStyle(.secondary)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            
            subtitleSection
            
            PlayerControls(
              model: model,
              backwardSeekInterval: backwardSeekInterval,
              forwardSeekInterval: forwardSeekInterval,
              onSeek: { time in seek(controller: controller, to: time) },
              onSeekBackward: { seekBackward(controller: controller) },
              onSeekForward: { seekForward(controller: controller) },
              onTogglePlayPause: { togglePlayPause(controller: controller) },
              onRateChange: { rate in setPlaybackRate(controller: controller, rate: rate) },
              onBackwardSeekIntervalChange: { interval in
                backwardSeekInterval = interval
              },
              onForwardSeekIntervalChange: { interval in
                forwardSeekInterval = interval
              },
              onSubtitleSeekBackward: { seekToPreviousSubtitle(controller: controller) },
              onSubtitleSeekForward: { seekToNextSubtitle(controller: controller) }
            )
          }
          .background(
            UnevenRoundedRectangle(
              topLeadingRadius: 24,
              bottomLeadingRadius: 0,
              bottomTrailingRadius: 0,
              topTrailingRadius: 24,
              style: .continuous
            )
            .foregroundStyle(.appPlayerBackground)
          )
        }        

      }

      .background(.appPlayerBackground)
      .toolbar {
       toolbarContent
      }
      .sheet(isPresented: $showDownloadView) {
        NavigationStack {
          DownloadView(videoID: videoID)
        }
      }
      .sheet(isPresented: $showTranscriptionSheet) {
        TranscriptionProgressSheet(
          transcriptionState: transcriptionState,
          onStart: {
            transcribeVideo()
          },
          onDismiss: {
            showTranscriptionSheet = false
          }
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedCueForExplanation) { cue in
        WordExplanationSheet(
          text: cue.text.htmlDecoded,
          context: cue.text.htmlDecoded
        )
      }
      .translationPresentation(
        isPresented: Binding(
          get: { selectedCueForTranslation != nil },
          set: { if !$0 { selectedCueForTranslation = nil } }
        ),
        text: selectedCueForTranslation?.text.htmlDecoded ?? ""
      )
      .onDisappear {
        // Stop playback and cancel tracking
        trackingTask?.cancel()
        trackingTask = nil
        if let controller = playerController {
          Task {
            await controller.pause()
          }
        }
      }
      .onChange(of: scenePhase) { oldPhase, newPhase in
        handleScenePhaseChange(from: oldPhase, to: newPhase)
      }
      .onChange(of: videoItem.isDownloaded) { oldValue, isDownloaded in
        // When download completes, automatically switch to local playback
        if isDownloaded, playbackSource == .youtube, let fileURL = videoItem.downloadedFileURL {
          localFileURL = fileURL
          switchPlaybackSource(to: .local)
        }
      }
      .onChange(of: currentSubtitles?.cues) { _, newCues in
        // Update model's cues when subtitles change
        model.cues = newCues ?? []
      }
    } else {
      ProgressView()
        .onAppear {
          loadVideo()
        }
    }
  }
  
  @ToolbarContentBuilder
  var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      HStack(spacing: 16) {
        SubtitleManagementView(
          videoID: videoID,
          subtitles: currentSubtitles,
          localFileURL: localFileURL,
          playbackSource: playbackSource,
          onSubtitlesImported: { subtitles in
            currentSubtitles = subtitles
            subtitleSource = .imported
          },
          onPlaybackSourceChange: { source in
            switchPlaybackSource(to: source)
          },
          onLocalVideoDeleted: {
            localFileURL = nil
          },
          onTranscribe: {
            showTranscriptionSheet = true
          },
          isTranscribing: isTranscribing
        )

        DownloadButton(
          state: downloadButtonState,
          onTap: { showDownloadView = true }
        )
      }
    }
  }

  // MARK: - Subtitle Section

  private var subtitleSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      SubtitleHeader(subtitleSource: subtitleSource)

      SubtitleListViewContainer(
        model: model,
        cues: currentSubtitles?.cues ?? [],
        isLoading: isLoadingTranscripts,
        transcriptionState: transcriptionState,
        error: transcriptError,
        onAction: { action in
          switch action {
          case .tap(let time):
            if let controller = playerController {
              seek(controller: controller, to: time)
            }
          case .setRepeatA(let time):
            model.repeatStartTime = time
          case .setRepeatB(let time):
            model.repeatEndTime = time
          case .explain(let cue):
            selectedCueForExplanation = cue
          case .translate(let cue):
            selectedCueForTranslation = cue
          }
        }
      )     
    }
  }

  // MARK: - Download Button State

  private var downloadButtonState: DownloadButton.State {
    // Check active download progress first
    if let progress = downloadManager.downloadProgress(for: videoID) {
      switch progress.state {
      case .pending:
        return .pending
      case .downloading:
        return .downloading(progress.fractionCompleted)
      case .paused:
        return .paused
      case .completed:
        return .completed
      case .failed, .cancelled:
        return .failed
      }
    }
    // Check persisted download status from VideoItem
    if videoItem.isDownloaded {
      return .completed
    }
    return .idle
  }

  // MARK: - Private Methods

  private func loadVideo() {
    // Prevent multiple loads
    guard playerController == nil else { return }

    // Check if video is downloaded
    if videoItem.isDownloaded,
       let fileURL = videoItem.downloadedFileURL {
      // Store local file URL for later switching
      localFileURL = fileURL
      // Use local file playback by default when available
      playerController = .local(LocalVideoPlayerController(url: fileURL))
      playbackSource = .local
    } else {
      // Use YouTube playback
      playerController = .youtube(YouTubeVideoPlayerController(videoID: videoID.rawValue))
      playbackSource = .youtube
    }

    if let controller = playerController {
      startTrackingTime(controller: controller)
    }
    fetchTranscripts(videoID: videoID)
  }

  private func fetchTranscripts(videoID: YouTubeContentID) {
    isLoadingTranscripts = true
    transcriptError = nil
    currentSubtitles = nil

    Task {
      // Check cache first
      let videoIDRaw = videoID.rawValue
      let descriptor = FetchDescriptor<VideoItem>(
        predicate: #Predicate { $0._videoID == videoIDRaw }
      )

      if let historyItem = try? modelContext.fetch(descriptor).first,
         let cached = historyItem.cachedSubtitles,
         !cached.cues.isEmpty {
        await MainActor.run {
          currentSubtitles = cached
          subtitleSource = .youtube
          isLoadingTranscripts = false
        }
        return
      }

      // Fetch from network
      do {
        let config = TranscriptConfig(lang: nil)
        let fetchedTranscripts = try await YoutubeTranscript.fetchTranscript(
          for: videoID.rawValue,
          config: config
        )

        let subtitles = fetchedTranscripts.toSwiftSubtitles()

        // Save to cache
        try? historyService.updateCachedSubtitles(videoID: videoID, subtitles: subtitles)

        await MainActor.run {
          currentSubtitles = subtitles
          subtitleSource = .youtube
          isLoadingTranscripts = false
        }
      } catch {
        await MainActor.run {
          transcriptError = error.localizedDescription
          isLoadingTranscripts = false
        }
      }
    }
  }

  private func startTrackingTime(controller: PlayerController) {
    // Cancel any existing tracking task
    trackingTask?.cancel()

    trackingTask = Task {
      // Initial delay to get duration
      try? await Task.sleep(for: .seconds(1))

      guard !Task.isCancelled else { return }

      let videoDuration = await controller.duration
      await MainActor.run {
        model.duration = videoDuration
      }

      // Main tracking loop
      while !Task.isCancelled {
        let timeValue = await controller.currentTime
        await MainActor.run {
          model.currentTime = timeValue
          model.isPlaying = controller.isPlaying
        }

        // Check A-B repeat loop
        if let loopStartTime = model.checkRepeatLoop() {
          await controller.seek(to: loopStartTime)
        }
        // Check end-of-video loop
        else if let loopStartTime = model.checkEndOfVideoLoop() {
          await controller.seek(to: loopStartTime)
        }

        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  private func seek(controller: PlayerController, to time: Double) {
    Task {
      await controller.seek(to: time)
    }
  }

  private func seekBackward(controller: PlayerController) {
    Task {
      let currentSeconds = await controller.currentTime
      let newSeconds = max(0, currentSeconds - backwardSeekInterval)
      await controller.seek(to: newSeconds)
    }
  }

  private func seekForward(controller: PlayerController) {
    Task {
      let currentSeconds = await controller.currentTime
      let newSeconds = currentSeconds + forwardSeekInterval
      await controller.seek(to: newSeconds)
    }
  }

  private func seekToPreviousSubtitle(controller: PlayerController) {
    Task {
      if let previousTime = model.previousSubtitleTime() {
        await controller.seek(to: previousTime)
      }
    }
  }

  private func seekToNextSubtitle(controller: PlayerController) {
    Task {
      if let nextTime = model.nextSubtitleTime() {
        await controller.seek(to: nextTime)
      }
    }
  }

  private func togglePlayPause(controller: PlayerController) {
    Task {
      if controller.isPlaying {
        await controller.pause()
        await MainActor.run { model.isPlaying = false }
      } else {
        await controller.play()
        await MainActor.run { model.isPlaying = true }
      }
    }
  }

  private func setPlaybackRate(controller: PlayerController, rate: Double) {
    Task {
      await controller.setPlaybackRate(rate)
      await MainActor.run {
        model.playbackRate = rate
      }
    }
  }

  private func switchPlaybackSource(to source: PlaybackSource) {
    guard source != playbackSource else { return }

    // Cancel existing tracking task
    trackingTask?.cancel()

    // Stop current player before switching
    if let currentController = playerController {
      Task {
        await currentController.pause()
      }
    }

    // Create new controller based on source
    switch source {
    case .youtube:
      playerController = .youtube(YouTubeVideoPlayerController(videoID: videoID.rawValue))
    case .local:
      guard let fileURL = localFileURL else { return }
      playerController = .local(LocalVideoPlayerController(url: fileURL))
    }

    playbackSource = source

    // Start new time tracking
    if let controller = playerController {
      startTrackingTime(controller: controller)
    }
  }

  private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
    guard let controller = playerController else { return }

    // When entering background
    if newPhase == .background {
      // Only pause YouTube playback in background
      // Local video playback continues in background (thanks to AVAudioSession .playback category)
      if case .youtube = controller {
        Task {
          await controller.pause()
          await MainActor.run {
            model.isPlaying = false
          }
        }
      }
      // Local video (.local case) continues playing in background - no action needed
    }
  }

  private func transcribeVideo() {
    guard let fileURL = localFileURL else { return }

    isTranscribing = true
    transcriptionState = .idle

    Task {
      do {
        let subtitles = try await TranscriptionService.shared.transcribe(
          fileURL: fileURL,
          locale: Locale(identifier: "en_US")
        ) { state in
          transcriptionState = state
        }

        // Update UI with transcribed subtitles and persist to SwiftData
        await MainActor.run {
          currentSubtitles = subtitles
          subtitleSource = .transcribed
          isTranscribing = false
          transcriptionState = .completed

          // Save to SwiftData for persistence across app launches
          try? historyService.updateCachedSubtitles(videoID: videoID, subtitles: subtitles)
        }

      } catch {
        await MainActor.run {
          transcriptionState = .failed(error.localizedDescription)
          isTranscribing = false
        }
      }
    }
  }
}

// MARK: - Nested Components

extension PlayerView {

  // MARK: - VideoPlayerSection

  struct VideoPlayerSection: View {
    let controller: PlayerController

    var body: some View {
      Group {
        switch controller {
        case .youtube(let controller):
          YouTubeVideoPlayer(controller: controller)
        case .local(let controller):
          LocalVideoPlayer(controller: controller)
        }
      }
      .aspectRatio(16 / 9, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
      .padding(.horizontal, 16)
      .padding(.top, 16)
    }
  }

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

        PlaybackControls(
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

  // MARK: - PlaybackControls

  struct PlaybackControls: View {
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

  // MARK: - RingSliderPointControl

  struct RingSliderPointControl: View {
    let label: String
    @Binding var value: Double
    let duration: Double
    let onSetToCurrent: () -> Void

    var body: some View {
      VStack(spacing: 8) {
        Text(label)
          .font(.system(.title2, design: .rounded).bold())
          .foregroundStyle(label == "A" ? .orange : .blue)

        RingSlider(
          value: $value,
          stride: 1,
          valueRange: 0...max(1, duration)
        )
        .frame(width: 80, height: 80)

        Text(formatTime(value))
          .font(.system(.caption, design: .monospaced))

        Button("Set to Current", action: onSetToCurrent)
          .font(.caption2)
          .buttonStyle(.bordered)
      }
      .padding(.vertical, 8)
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
            label: "A",
            value: $startValue,
            duration: model.duration,
            onSetToCurrent: { model.setRepeatStartToCurrent() }
          )

          RingSliderPointControl(
            label: "B",
            value: $endValue,
            duration: model.duration,
            onSetToCurrent: { model.setRepeatEndToCurrent() }
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

  // MARK: - SubtitleHeader

  struct SubtitleHeader: View {
    let subtitleSource: SubtitleSource

    var body: some View {
      Group {
        if subtitleSource != .youtube {
          HStack {
            Text("(\(subtitleSource.displayName))")
              .font(.caption)
              .foregroundStyle(.orange)
            Spacer()
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
      }
    }
  }

  // MARK: - TranscriptionProgressSheet

  struct TranscriptionProgressSheet: View {
    let transcriptionState: TranscriptionService.TranscriptionState
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
      VStack(spacing: 24) {
        // Title
        Text("Transcribe Audio")
          .font(.headline)

        // State-based content
        Group {
          switch transcriptionState {
          case .idle:
            VStack(spacing: 16) {
              Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

              Text("Convert video audio to subtitles using Apple's Speech Recognition.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

              Button {
                onStart()
              } label: {
                Text("Start Transcription")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .padding(.horizontal)
            }

          case .preparingAssets:
            VStack(spacing: 16) {
              ProgressView()
                .scaleEffect(1.5)

              Text("Preparing speech recognition model...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

          case .transcribing(let progress):
            VStack(spacing: 16) {
              ProgressView(value: progress) {
                Text("Transcribing...")
              } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Text("Processing audio...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

          case .completed:
            VStack(spacing: 16) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

              Text("Transcription completed successfully!")
                .font(.subheadline)
                .foregroundStyle(.secondary)

              Button {
                onDismiss()
              } label: {
                Text("Done")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .padding(.horizontal)
            }

          case .failed(let message):
            VStack(spacing: 16) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

              Text("Transcription failed")
                .font(.headline)

              Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

              Button {
                onDismiss()
              } label: {
                Text("Close")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
              .padding(.horizontal)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding()
    }
  }

  // MARK: - DownloadButton

  struct DownloadButton: View {
    enum State: Equatable {
      case idle
      case pending
      case downloading(Double)
      case paused
      case completed
      case failed
    }

    let state: State
    let onTap: () -> Void

    var body: some View {
      Button(action: onTap) {
        buttonContent
      }
    }

    @ViewBuilder
    private var buttonContent: some View {
      switch state {
      case .idle:
        Label("Download", systemImage: "arrow.down.circle")

      case .pending:
        Label {
          Text("Pending")
        } icon: {
          ProgressView()
            .scaleEffect(0.8)
        }

      case .downloading(let progress):
        Label {
          Text("\(Int(progress * 100))%")
        } icon: {
          ZStack {
            Circle()
              .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            Circle()
              .trim(from: 0, to: progress)
              .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .rotationEffect(.degrees(-90))
          }
          .frame(width: 18, height: 18)
        }

      case .paused:
        Label("Paused", systemImage: "pause.circle.fill")

      case .completed:
        Label("Downloaded", systemImage: "checkmark.circle.fill")

      case .failed:
        Label("Retry", systemImage: "exclamationmark.circle")
      }
    }
  }
}

// MARK: - Playback Source

enum PlaybackSource {
  case youtube
  case local

  var displayName: String {
    switch self {
    case .youtube: return "YouTube"
    case .local: return "Local"
    }
  }
}

// MARK: - Subtitle Source

enum SubtitleSource {
  case youtube
  case imported
  case saved
  case transcribed

  var displayName: String {
    switch self {
    case .youtube: return "YouTube"
    case .imported: return "Imported"
    case .saved: return "Saved"
    case .transcribed: return "Transcribed"
    }
  }
}

#Preview {
  NavigationStack {
    let item = VideoItem(
      videoID: "oRc4sndVaWo",
      url: "https://www.youtube.com/watch?v=oRc4sndVaWo",
      title: "Preview Video"
    )
    PlayerView(videoItem: item)
  }
}

