//
//  ContentView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI
import YouTubePlayerKit

struct ContentView: View {
  @State private var urlText: String = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"  
  @State private var youtubePlayer: YouTubePlayer?
  
  var body: some View {
    VStack(spacing: 0) {
      // URL Input Section
      HStack {
        TextField("Enter YouTube URL", text: $urlText)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            loadURL()
          }
        
        Button("Load") {
          loadURL()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
      
      // YouTube Player Section
      if let player = youtubePlayer {
        YouTubePlayerView(player)
          .frame(minWidth: 400, minHeight: 300)
      } else {
        ContentUnavailableView(
          "No Video Loaded",
          systemImage: "play.rectangle",
          description: Text("Enter a YouTube URL above to start")
        )
      }
    }
  }
  
  private func loadURL() {
    guard let url = URL(string: urlText), !urlText.isEmpty else {
      return
    }
    
    // Extract video ID and create YouTubePlayer
    if let videoID = YouTubeURLParser.extractVideoID(from: url) {
      youtubePlayer = YouTubePlayer(source: .video(id: videoID))
    }
  }
}

#Preview {
  ContentView()
}
