import Foundation
import SwiftData

@Model
final class VideoHistoryItem {
  var id: UUID
  var videoID: String
  var url: String
  var title: String?
  var author: String?
  var thumbnailURL: String?
  var timestamp: Date
  
  init(videoID: String, url: String, title: String? = nil, author: String? = nil, thumbnailURL: String? = nil) {
    self.id = UUID()
    self.videoID = videoID
    self.url = url
    self.title = title
    self.author = author
    self.thumbnailURL = thumbnailURL
    self.timestamp = Date()
  }
}
