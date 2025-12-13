#!/bin/bash

set -e  # エラーが発生したら即座に終了
set -o pipefail  # パイプラインのエラーを検知

# 設定
APPLE_ID="muukii.app@gmail.com"
SCHEME="YouTubeSubtitle"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/YouTubeSubtitle.xcarchive"
EXPORT_PATH="./build"
IPA_PATH="./build/YouTubeSubtitle.ipa"

# Team情報
TEAM_ID="KU2QEJ9K3Z"
APP_IDENTIFIER="app.muukii.verse"

# xcbeautifyの確認
if ! command -v xcbeautify &> /dev/null; then
  echo "⚠️  xcbeautify not found. Install with: brew install xcbeautify"
  echo "Falling back to raw xcodebuild output..."
  BEAUTIFY_CMD="cat"
else
  BEAUTIFY_CMD="xcbeautify"
fi

echo "🏗️  Building and archiving..."

# buildディレクトリをクリーンアップ
rm -rf ./build
mkdir -p ./build

# アーカイブを作成
xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" | $BEAUTIFY_CMD

echo "✅ Archive created: $ARCHIVE_PATH"

# ExportOptions.plistを作成
cat > ./build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
EOF

echo "📦 Exporting IPA..."

# IPAをエクスポート
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ./build/ExportOptions.plist | $BEAUTIFY_CMD

echo "✅ IPA created: $EXPORT_PATH/$SCHEME.ipa"

# TestFlightにアップロード
echo "🚀 Uploading to TestFlight..."

# App Store Connect API Keyの環境変数をチェック
if [ -z "$APP_STORE_CONNECT_API_KEY_PATH" ] && [ -z "$APPLE_ID" ]; then
  echo "⚠️  Error: Authentication credentials not set"
  echo ""
  echo "Method 1 - App Store Connect API (Recommended):"
  echo "1. Create API key at: https://appstoreconnect.apple.com/access/integrations/api"
  echo "2. Download the .p8 file"
  echo "3. Set environment variables:"
  echo "   export APP_STORE_CONNECT_API_KEY_PATH='/path/to/AuthKey_XXXXXXXXXX.p8'"
  echo "   export APP_STORE_CONNECT_API_KEY_ID='XXXXXXXXXX'"
  echo "   export APP_STORE_CONNECT_API_ISSUER_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
  echo ""
  echo "Method 2 - App-Specific Password:"
  echo "1. Generate at: https://appleid.apple.com/account/manage"
  echo "2. Set environment variables:"
  echo "   export APPLE_ID='muukii.app@gmail.com'"
  echo "   export APP_SPECIFIC_PASSWORD='xxxx-xxxx-xxxx-xxxx'"
  exit 1
fi

# App Store Connect APIキーを使用してアップロード（推奨）
if [ -n "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
  echo "Using App Store Connect API Key..."
  xcrun altool --upload-app \
    --type ios \
    --file "$EXPORT_PATH/$SCHEME.ipa" \
    --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
    --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID"
# App-Specificパスワードを使用
elif [ -n "$APPLE_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ]; then
  echo "Using App-Specific Password..."
  xcrun altool --upload-app \
    --type ios \
    --file "$EXPORT_PATH/$SCHEME.ipa" \
    --username "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD"
else
  echo "❌ Error: Incomplete authentication credentials"
  exit 1
fi

echo "🎉 Successfully uploaded to TestFlight!"
