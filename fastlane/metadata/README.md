# App Store メタデータ管理

このディレクトリには、App Storeに提出する際に使用するメタデータファイルが含まれています。

## ディレクトリ構造

```
fastlane/metadata/
├── en-US/           # 英語（米国）
│   ├── name.txt
│   ├── subtitle.txt
│   ├── description.txt
│   ├── keywords.txt
│   └── promotional_text.txt
└── ja/              # 日本語
    ├── name.txt
    ├── subtitle.txt
    ├── description.txt
    ├── keywords.txt
    └── promotional_text.txt
```

## メタデータファイルの説明

### name.txt
- **内容**: アプリ名
- **文字数制限**: 30文字以内
- **例**: `Verse`

### subtitle.txt
- **内容**: アプリのサブタイトル（App Store検索で表示）
- **文字数制限**: 30文字以内
- **例**: `YouTube Subtitle Player` / `YouTube字幕プレイヤー`

### description.txt
- **内容**: App Storeに表示されるアプリの詳細説明
- **文字数制限**: 4,000文字以内
- **推奨**: 機能の箇条書き、ターゲットユーザーの明示

### keywords.txt
- **内容**: App Store検索用のキーワード（カンマ区切り）
- **文字数制限**: 100文字以内（カンマとスペースを含む）
- **注意**: スペース区切りではなくカンマ区切り

### promotional_text.txt
- **内容**: プロモーショナルテキスト（アプリ更新なしで変更可能）
- **文字数制限**: 170文字以内
- **用途**: 期間限定セール、新機能の告知など

## メタデータの編集方法

1. 対応する言語フォルダ内のテキストファイルを直接編集
2. 文字数制限に注意
3. 変更をコミットしてバージョン管理

```bash
# ファイルを編集
vi fastlane/metadata/ja/description.txt

# 変更をコミット
git add fastlane/metadata/
git commit -m "Update Japanese app description"
```

## App Store Connectへのアップロード

### fastlaneを使用する場合

```bash
# メタデータのみをアップロード（ビルドなし）
fastlane deliver --skip_binary_upload --skip_screenshots

# 特定の言語のみをアップロード
fastlane deliver --skip_binary_upload --languages "ja"
```

### 手動でアップロードする場合

1. App Store Connectにログイン
2. 対象アプリを選択
3. 「App情報」または「バージョン情報」を選択
4. 各言語を選択し、ファイルの内容をコピー&ペースト

## 新しい言語を追加する

1. 言語コードのディレクトリを作成（例: `de-DE`はドイツ語）
2. 必要なメタデータファイルを作成
3. 各ファイルに翻訳されたコンテンツを記入

```bash
# ドイツ語のメタデータディレクトリを作成
mkdir -p fastlane/metadata/de-DE
cp -r fastlane/metadata/en-US/* fastlane/metadata/de-DE/
# その後、各ファイルを翻訳
```

## 言語コード一覧

- `en-US`: 英語（米国）
- `ja`: 日本語
- `zh-Hans`: 簡体字中国語
- `zh-Hant`: 繁体字中国語
- `ko`: 韓国語
- `de-DE`: ドイツ語
- `fr-FR`: フランス語
- `es-ES`: スペイン語

完全な言語コードリストは[Appleの公式ドキュメント](https://developer.apple.com/documentation/appstoreconnectapi/list_all_bundle_id_capabilities)を参照してください。

## ベストプラクティス

1. **定期的な見直し**: 新機能追加時にメタデータを更新
2. **A/Bテスト**: promotional_text.txtで異なる訴求を試す
3. **キーワード最適化**: 定期的にキーワードの効果を分析
4. **翻訳品質**: ネイティブスピーカーによるレビューを推奨
5. **バージョン管理**: 変更履歴を明確にコミットメッセージで記録

## 注意事項

- App Storeのレビューガイドラインに違反する内容は記載しない
- 誇張表現や虚偽の情報を避ける
- 競合他社名を使用しない
- 価格や期間限定の情報はpromotional_textのみに記載
