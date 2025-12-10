import Foundation
import SwiftData
import TypedIdentifier

// MARK: - Video Item

@Model
final class VideoItem: TypedIdentifiable {

  typealias TypedIdentifierRawValue = UUID

  var typedID: TypedIdentifier<VideoItem> {
    .init(id)
  }

  var id: UUID

  // Database storage (primitive String for SwiftData optimization)
  internal var _videoID: String

  // Public API (type-safe)
  var videoID: YouTubeContentID {
    get { YouTubeContentID(rawValue: _videoID) }
    set { _videoID = newValue.rawValue }
  }

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

  // MARK: - Playback Resume

  /// Last playback position in seconds for resume functionality
  var lastPlaybackPosition: Double?

  // MARK: - Download State Relationship

  /// Active download state (exists only during download).
  /// When download completes, fails, or is cancelled, this entity is deleted.
  @Relationship(deleteRule: .cascade, inverse: \DownloadStateEntity.videoItem)
  var downloadState: DownloadStateEntity?

  // MARK: - Computed Download Properties

  /// Whether there is an active download in progress
  var hasActiveDownload: Bool {
    downloadState != nil
  }

  /// Whether the video has been downloaded
  var isDownloaded: Bool {
    downloadedFileName != nil
  }

  var downloadedFileURL: URL? {
    guard let fileName = downloadedFileName else { return nil }
    return URL.documentsDirectory.appendingPathComponent(fileName)
  }

  @Transient private var _cachedSubtitles: Subtitle?

  var cachedSubtitles: Subtitle? {
    get {
      if let cached = _cachedSubtitles {
        return cached
      }
      guard let data = transcriptData else { return nil }
      _cachedSubtitles = try? JSONDecoder().decode(Subtitle.self, from: data)
      return _cachedSubtitles
    }
    set {
      _cachedSubtitles = newValue
      transcriptData = newValue.flatMap { try? JSONEncoder().encode($0) }
    }
  }

  init(
    videoID: YouTubeContentID,
    url: String,
    title: String? = nil,
    author: String? = nil,
    thumbnailURL: String? = nil
  ) {
    self.id = UUID()
    self._videoID = videoID.rawValue  // Store as primitive String
    self.url = url
    self.title = title
    self.author = author
    self.thumbnailURL = thumbnailURL
    self.timestamp = Date()
  }
}
