# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YouTubeSubtitle is a SwiftUI-based multi-platform application targeting iOS and macOS. This is a standard Xcode project (not using Tuist or SPM packages).

## Build Commands

### Building the project
```bash
xcodebuild -project YouTubeSubtitle.xcodeproj -scheme YouTubeSubtitle -configuration Debug build
```

### Running tests
```bash
xcodebuild -project YouTubeSubtitle.xcodeproj -scheme YouTubeSubtitle test
```

### Opening in Xcode
```bash
open YouTubeSubtitle.xcodeproj
```

## Project Structure

- `YouTubeSubtitle/YouTubeSubtitleApp.swift` - Main app entry point with `@main`
- `YouTubeSubtitle/ContentView.swift` - Root SwiftUI view
- `YouTubeSubtitle.xcodeproj/` - Xcode project configuration

## Development Notes

- This is a standard Xcode project (not Tuist or SPM-based)
- Uses SwiftUI as the UI framework
- Target platforms: iOS and macOS
- Single scheme: `YouTubeSubtitle`
- Default build configurations: Debug and Release
