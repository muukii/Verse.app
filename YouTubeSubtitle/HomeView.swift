//
//  HomeView.swift
//  YouTubeSubtitle
//
//  Created by Hiroshi Kimura on 2025/11/30.
//

import SwiftUI

struct HomeView: View {
  @State private var urlText: String = "https://www.youtube.com/watch?v=oRc4sndVaWo"
  @State private var selectedVideoID: String?
  
  var body: some View {
    NavigationStack {
      VStack {
        Spacer()
        
        VStack(spacing: 20) {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.blue)
          
          Text("YouTube Subtitle Player")
            .font(.largeTitle)
            .fontWeight(.bold)
          
          Text("Enter a YouTube URL to get started")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          
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
          .frame(maxWidth: 500)
          .padding()
        }
        
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationDestination(item: $selectedVideoID) { videoID in
        PlayerView(videoID: videoID)
      }
    }
  }
  
  private func loadURL() {
    guard let url = URL(string: urlText), !urlText.isEmpty else {
      return
    }
    
    // Extract video ID and navigate to player
    if let videoID = YouTubeURLParser.extractVideoID(from: url) {
      selectedVideoID = videoID
    }
  }
}

#Preview {
  HomeView()
}
