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

  /// Returns true when transcription is actively in progress (preparing or transcribing)
  /// Used to prevent interactive dismissal of the sheet during processing
  private var isTranscriptionInProgress: Bool {
    switch transcriptionState {
    case .preparingAssets, .transcribing:
      return true
    case .idle, .completed, .failed:
      return false
    }
  }

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
        .presentationDragIndicator(isTranscriptionInProgress ? .hidden : .visible)
        .interactiveDismissDisabled(isTranscriptionInProgress)
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

