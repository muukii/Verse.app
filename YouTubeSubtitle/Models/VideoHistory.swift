import Foundation
import SwiftData
import SwiftSubtitles

@Model
final class VideoHistoryItem {
  var id: UUID
  var videoID: String
  var url: String
  var title: String?
  var author: String?
  var thumbnailURL: String?
  var timestamp: Date

  // Transcript cache
  var transcriptData: Data?
  var transcriptLanguage: String?

  // Downloaded file (relative path from Documents directory)
  var downloadedFileName: String?

  var downloadedFileURL: URL? {
    guard let fileName = downloadedFileName else { return nil }
    return URL.documentsDirectory.appendingPathComponent(fileName)
  }

  @Transient private var _cachedSubtitles: Subtitles?

  var cachedSubtitles: Subtitles? {
    get {
      if let cached = _cachedSubtitles {
        return cached
      }
      guard let data = transcriptData else { return nil }
      _cachedSubtitles = try? JSONDecoder().decode(Subtitles.self, from: data)
      return _cachedSubtitles
    }
    set {
      _cachedSubtitles = newValue
      transcriptData = newValue.flatMap { try? JSONEncoder().encode($0) }
    }
  }

  init(
    videoID: String,
    url: String,
    title: String? = nil,
    author: String? = nil,
    thumbnailURL: String? = nil
  ) {
    self.id = UUID()
    self.videoID = videoID
    self.url = url
    self.title = title
    self.author = author
    self.thumbnailURL = thumbnailURL
    self.timestamp = Date()
  }
}
