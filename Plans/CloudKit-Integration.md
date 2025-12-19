# Plan: CloudKit Integration for SwiftData Models

## 目的
全SwiftDataモデル（VideoItem, VocabularyItem, TranscriptionSession, TranscriptionEntry, DownloadStateEntity）をCloudKitで同期し、複数デバイス間でデータを共有する。

## 現状分析

### CloudKit互換性ステータス
| モデル | ステータス | 課題 |
|--------|-----------|------|
| VocabularyItem | ✅ 準備完了 | なし |
| TranscriptionSession | ✅ 準備完了 | なし |
| TranscriptionEntry | ✅ 準備完了 | なし |
| DownloadStateEntity | ⚠️ 修正必要 | `streamURL`, `fileExtension`がnon-optionalでデフォルトなし |
| VideoItem | ⚠️ 修正必要 | `url`がnon-optionalでデフォルトなし |

### 既存エンタイトルメント
- App Sandbox ✅
- Network Client ✅
- CloudKit ❌ **未設定**

## 実装ステップ

### Step 1: Xcodeでの設定（手動）
1. **Signing & Capabilities** で「iCloud」を追加
2. **CloudKit** にチェック
3. **Container** を選択: `iCloud.app.muukii.verse`

### Step 2: モデルの互換性修正

#### VideoItem.swift
```swift
// 変更前
let url: String

// 変更後
var url: String = ""
```

#### DownloadStateEntity.swift
```swift
// 変更前
let streamURL: String
let fileExtension: String

// 変更後（2つの選択肢）

// Option A: デフォルト値を追加
var streamURL: String = ""
var fileExtension: String = ""

// Option B: Optionalに変更（ダウンロード状態はローカル専用なので同期不要かも）
// → DownloadStateEntityは同期対象から除外する方が自然
```

### Step 3: ModelContainer設定の変更

#### YouTubeSubtitleApp.swift
```swift
// 変更前
modelContainer = try ModelContainer(for: schema)

// 変更後
let config = ModelConfiguration(
  cloudKitDatabase: .private("iCloud.app.muukii.verse")
)
modelContainer = try ModelContainer(for: schema, configurations: config)
```

### Step 4: ローカル専用データの分離（推奨）

`DownloadStateEntity`はダウンロード進行状態を管理するエフェメラルなデータなので、CloudKit同期対象から除外することを推奨：

```swift
// CloudKit同期対象
let syncedSchema = Schema([
  VideoItem.self,
  VocabularyItem.self,
  TranscriptionSession.self,
  TranscriptionEntry.self,
])

// ローカル専用
let localSchema = Schema([
  DownloadStateEntity.self,
])

let cloudConfig = ModelConfiguration(
  "CloudSync",
  schema: syncedSchema,
  cloudKitDatabase: .private("iCloud.app.muukii.verse")
)

let localConfig = ModelConfiguration(
  "LocalOnly",
  schema: localSchema,
  isStoredInMemoryOnly: false
)

modelContainer = try ModelContainer(
  for: syncedSchema + localSchema,
  configurations: [cloudConfig, localConfig]
)
```

## 変更ファイル一覧

1. `YouTubeSubtitle.entitlements` - CloudKitエンタイトルメント追加（Xcode経由）
2. `YouTubeSubtitle/Models/VideoItem.swift` - `url`プロパティ修正
3. `YouTubeSubtitle/Models/DownloadStateEntity.swift` - プロパティ修正 or スキーマ分離
4. `YouTubeSubtitle/App/YouTubeSubtitleApp.swift` - ModelContainer設定変更

## 注意事項

### データサイズ制限
- CloudKitレコードサイズ上限: 1MB
- `transcriptData`（字幕JSON）が大きい場合は問題になる可能性
- 必要に応じてCKAssetとして別途保存

### 同期の挙動
- CloudKitは結果整合性（Eventually Consistent）
- ネットワーク接続がない場合はローカルに保存され、接続時に同期
- コンフリクトはSwiftDataが自動解決（最新のタイムスタンプが優先）

### テスト
- 開発時は`Tips.resetDatastore()`のように`ModelContainer`のテストリセットを用意
- CloudKit Dashboardでレコードを確認可能

## 決定事項

1. **DownloadStateEntity** → 除外（ダウンロード状態はデバイス固有）
2. **iCloudコンテナ名** → `iCloud.app.muukii.verse`
