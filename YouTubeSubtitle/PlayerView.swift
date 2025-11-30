//
//  PlayerView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit
import YoutubeTranscript

struct PlayerView: View {
  let videoID: String
  
  @State private var youtubePlayer: YouTubePlayer?
  @State private var seekTimeText: String = ""
  @State private var currentTime: Double = 0
  @State private var duration: Double = 0
  @State private var isTrackingTime: Bool = false
  @State private var transcripts: [TranscriptResponse] = []
  @State private var isLoadingTranscripts: Bool = false
  @State private var transcriptError: String?
  @State private var scrollPosition: Double?
  
  var body: some View {
    HStack(spacing: 0) {
      // Left side: Player and controls
      VStack(spacing: 0) {
        if let player = youtubePlayer {
          YouTubePlayerView(player)
            .frame(minWidth: 400, minHeight: 300)
          
          // Time Display
          HStack {
            Text(formatTime(currentTime))
              .font(.system(.body, design: .monospaced))
            Text("/")
              .foregroundStyle(.secondary)
            Text(formatTime(duration))
              .font(.system(.body, design: .monospaced))
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 8)
          
          // Playback Controls
          VStack(spacing: 12) {
            HStack(spacing: 20) {
              Button {
                seekBackward(player: player)
              } label: {
                Label("10s", systemImage: "gobackward.10")
              }
              .buttonStyle(.bordered)
              
              Button {
                togglePlayPause(player: player)
              } label: {
                Label("Play/Pause", systemImage: "playpause.fill")
              }
              .buttonStyle(.borderedProminent)
              
              Button {
                seekForward(player: player)
              } label: {
                Label("10s", systemImage: "goforward.10")
              }
              .buttonStyle(.bordered)
            }
            
            // Jump to specific time
            HStack {
              TextField("Jump to time (seconds)", text: $seekTimeText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit {
                  jumpToTime(player: player)
                }
              
              Button("Jump") {
                jumpToTime(player: player)
              }
              .buttonStyle(.bordered)
            }
          }
          .padding()
        }
      }
      
      // Right side: Transcript list
      VStack(alignment: .leading, spacing: 0) {
        Text("Subtitles")
          .font(.headline)
          .padding()
        
        Divider()
        
        if isLoadingTranscripts {
          ProgressView("Loading subtitles...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = transcriptError {
          VStack {
            Image(systemName: "exclamationmark.triangle")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text("Failed to load subtitles")
              .font(.headline)
            Text(error)
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if transcripts.isEmpty {
          ContentUnavailableView(
            "No Subtitles",
            systemImage: "text.bubble",
            description: Text("No subtitles available for this video")
          )
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(Array(transcripts.enumerated()), id: \.offset) { index, transcript in
                let isCurrent = isCurrentSubtitle(offset: transcript.offset)
                
                VStack(alignment: .leading, spacing: 4) {
                  Text(formatTime(transcript.offset))
                    .font(.caption)
                    .foregroundStyle(isCurrent ? .white : .secondary)
                  Text(transcript.text)
                    .font(.body)
                    .foregroundStyle(isCurrent ? .white : .primary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isCurrent ? Color.blue : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .onTapGesture {
                  if let player = youtubePlayer {
                    jumpToSubtitle(player: player, offset: transcript.offset)
                  }
                }
                .id(transcript.offset)
              }
            }
            .padding()
          }
          .scrollPosition(id: $scrollPosition, anchor: .center)
          .onChange(of: currentTime) { _, _ in
            updateScrollPosition()
          }
        }
      }
      .frame(minWidth: 300, maxWidth: 400)
      .background(Color(white: 0.95))
    }
    .onAppear {
      loadVideo()
    }
  }
  
  private func loadVideo() {
    let player = YouTubePlayer(source: .video(id: videoID))
    youtubePlayer = player
    
    // Start tracking time
    startTrackingTime(player: player)
    
    // Fetch transcripts
    fetchTranscripts(videoID: videoID)
  }
  
  private func fetchTranscripts(videoID: String) {
    isLoadingTranscripts = true
    transcriptError = nil
    transcripts = []
    
    Task {
      do {
        let config = TranscriptConfig(lang: "en")
        let fetchedTranscripts = try await YoutubeTranscript.fetchTranscript(for: videoID, config: config)
        
        await MainActor.run {
          transcripts = fetchedTranscripts
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
  
  private func startTrackingTime(player: YouTubePlayer) {
    isTrackingTime = true
    
    // Fetch duration once when video loads
    Task {
      // Wait a bit for video to load
      try? await Task.sleep(for: .seconds(1))
      
      if let videoDuration = try? await player.getDuration() {
        await MainActor.run {
          duration = videoDuration.converted(to: .seconds).value
        }
      }
    }
    
    // Start periodic updates for current time
    Task {
      while isTrackingTime {
        if let time = try? await player.getCurrentTime() {
          await MainActor.run {
            currentTime = time.converted(to: .seconds).value
          }
        }
        
        // Update every 0.5 seconds
        try? await Task.sleep(for: .milliseconds(500))
      }
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
  
  private func seekBackward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = max(0, currentSeconds - 10)
        try? await player.seek(to: Measurement(value: newSeconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      }
    }
  }
  
  private func seekForward(player: YouTubePlayer) {
    Task {
      if let currentTime = try? await player.getCurrentTime() {
        let currentSeconds = currentTime.converted(to: .seconds).value
        let newSeconds = currentSeconds + 10
        try? await player.seek(to: Measurement(value: newSeconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      }
    }
  }
  
  private func togglePlayPause(player: YouTubePlayer) {
    Task {
      if let state = try? await player.playbackState {
        switch state {
        case .playing:
          try? await player.pause()
        case .paused, .unstarted, .ended, .buffering, .cued:
          try? await player.play()
        }
      } else {
        try? await player.play()
      }
    }
  }
  
  private func jumpToTime(player: YouTubePlayer) {
    guard let seconds = Double(seekTimeText), seconds >= 0 else {
      return
    }
    
    Task {
      try? await player.seek(to: Measurement(value: seconds, unit: UnitDuration.seconds), allowSeekAhead: true)
      seekTimeText = ""
    }
  }
  
  private func jumpToSubtitle(player: YouTubePlayer, offset: Double) {
    Task {
      try? await player.seek(to: Measurement(value: offset, unit: UnitDuration.seconds), allowSeekAhead: true)
    }
  }
  
  private func isCurrentSubtitle(offset: Double) -> Bool {
    guard !transcripts.isEmpty else { return false }
    
    if let currentIndex = transcripts.firstIndex(where: { $0.offset > currentTime }) {
      if currentIndex > 0 {
        let previousTranscript = transcripts[currentIndex - 1]
        return previousTranscript.offset == offset
      }
      return false
    } else {
      if let lastTranscript = transcripts.last {
        return lastTranscript.offset == offset && currentTime >= offset
      }
      return false
    }
  }
  
  private func updateScrollPosition() {
    guard !transcripts.isEmpty else { return }
    
    if let currentIndex = transcripts.firstIndex(where: { $0.offset > currentTime }), currentIndex > 0 {
      let currentTranscript = transcripts[currentIndex - 1]
      scrollPosition = currentTranscript.offset
    } else if let lastTranscript = transcripts.last, currentTime >= lastTranscript.offset {
      scrollPosition = lastTranscript.offset
    }
  }
}

#Preview {
  PlayerView(videoID: "oRc4sndVaWo")
}
