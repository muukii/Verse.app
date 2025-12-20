# Plan: VideoItem Playlist機能の設計

## 目的
VideoItemsをPlaylist（プレイリスト）でグループ化し、以下の用途に対応する：
- 学習テーマ別の整理（文法、リスニング、ビジネス英語など）
- 進捗管理（未視聴/視聴中/完了）
- お気に入り管理

## データモデル設計

### 新規モデル: Playlist

```swift
@Model
final class Playlist {
  var id: UUID = UUID()
  var name: String = ""
  var icon: String? = nil          // SF Symbol名
  var color: String? = nil          // Hex色コード
  var createdAt: Date = Date()
  var updatedAt: Date = Date()

  // 順序を保持するための中間テーブルを使用
  @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
  var entries: [PlaylistEntry] = []

  // 計算プロパティ
  var videoCount: Int { entries.count }
  var videos: [VideoItem] { entries.sorted { $0.order < $1.order }.compactMap { $0.video } }
}
```

### 新規モデル: PlaylistEntry（中間テーブル）

```swift
@Model
final class PlaylistEntry {
  var id: UUID = UUID()
  var order: Int = 0               // 順序
  var addedAt: Date = Date()

  // リレーション
  var playlist: Playlist?
  var video: VideoItem?

  init(playlist: Playlist, video: VideoItem, order: Int) {
    self.playlist = playlist
    self.video = video
    self.order = order
  }
}
```

### VideoItemへの追加

```swift
// VideoItem.swift に追加
@Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.video)
var playlistEntries: [PlaylistEntry] = []

// 計算プロパティ
var playlists: [Playlist] {
  playlistEntries.compactMap { $0.playlist }
}
```

## リレーション構造

```
Playlist ←1----*→ PlaylistEntry ←*----1→ VideoItem
          (owns)                   (references)

- Playlist削除 → PlaylistEntry削除（cascade）
- VideoItem削除 → PlaylistEntry削除（cascade） ✅ 決定済み
- PlaylistEntry削除 → Playlist/VideoItemは残る
```

### なぜ中間テーブル（PlaylistEntry）を使うか

1. **順序の保持** - `order`フィールドで並び順を管理
2. **追加日時の記録** - いつプレイリストに追加したか
3. **同じ動画を複数プレイリストに** - 多対多の実現
4. **将来の拡張性** - 進捗状態、メモなどをエントリごとに持てる

## UI設計案

### HomeViewへの統合

```
┌─────────────────────────────────────────┐
│  [すべて] [Playlist1] [Playlist2] [+]   │  ← セグメント/タブ
├─────────────────────────────────────────┤
│  📺 Video 1                             │
│  📺 Video 2                             │
│  📺 Video 3                             │
│  ...                                    │
└─────────────────────────────────────────┘
```

### Playlist管理画面

- プレイリスト一覧
- 新規作成（名前、アイコン、色）
- 編集/削除
- 並べ替え（ドラッグ&ドロップ）

### コンテキストメニュー

VideoHistoryCellの長押しメニューに追加：
- 「プレイリストに追加」
- 「プレイリストから削除」

## サービス層

### PlaylistService

```swift
@Observable @MainActor
final class PlaylistService {
  private let modelContext: ModelContext

  // CRUD
  func createPlaylist(name: String, icon: String?, color: String?) -> Playlist
  func updatePlaylist(_ playlist: Playlist, name: String, icon: String?, color: String?)
  func deletePlaylist(_ playlist: Playlist)

  // エントリ管理
  func addVideo(_ video: VideoItem, to playlist: Playlist)
  func removeVideo(_ video: VideoItem, from playlist: Playlist)
  func reorderVideos(in playlist: Playlist, from: IndexSet, to: Int)

  // クエリ
  func playlists(containing video: VideoItem) -> [Playlist]
}
```

## CloudKit互換性

PlaylistとPlaylistEntryは以下の条件を満たす：
- ✅ 全プロパティにデフォルト値あり
- ✅ サポートされる型のみ使用（UUID, String, Date, Int）
- ✅ オプショナルのリレーション

→ CloudKit同期対象に追加可能

## 変更ファイル一覧

### 新規作成
1. `YouTubeSubtitle/Models/Playlist.swift` - Playlistモデル
2. `YouTubeSubtitle/Models/PlaylistEntry.swift` - 中間テーブル
3. `YouTubeSubtitle/Services/PlaylistService.swift` - サービス層
4. `YouTubeSubtitle/Features/Playlist/PlaylistListView.swift` - 一覧画面
5. `YouTubeSubtitle/Features/Playlist/PlaylistDetailView.swift` - 詳細画面
6. `YouTubeSubtitle/Features/Playlist/CreatePlaylistSheet.swift` - 作成シート

### 変更
1. `YouTubeSubtitle/Models/VideoItem.swift` - playlistEntriesリレーション追加
2. `YouTubeSubtitle/App/YouTubeSubtitleApp.swift` - Schema追加
3. `YouTubeSubtitle/Features/Home/HomeView.swift` - タブ/フィルター追加
4. `YouTubeSubtitle/Features/Home/VideoHistoryCell.swift` - コンテキストメニュー追加

## 実装フェーズ

### Phase 1: データモデル
- Playlist, PlaylistEntryモデル作成
- VideoItemにリレーション追加
- Schema登録

### Phase 2: サービス層
- PlaylistService実装
- CRUD操作

### Phase 3: UI - 基本
- プレイリスト一覧/作成/編集
- 動画追加/削除

### Phase 4: UI - 統合
- HomeViewへのフィルター統合
- コンテキストメニュー

### Phase 5: CloudKit対応
- 既存のCloudKit計画に統合

## 決定事項

1. **VideoItem削除時の挙動** → `cascade`（PlaylistEntryも削除）
2. **デフォルトプレイリスト** → 自動作成しない（ユーザーに委ねる）
