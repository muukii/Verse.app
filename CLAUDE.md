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

## Documentation Policy

### When to Update SPECIFICATION.md

**IMPORTANT**: Whenever you make functional changes to the application, you MUST update `Docs/SPECIFICATION.md` to reflect those changes.

Update the specification when:
- Adding new features (UI components, screens, functionality)
- Modifying existing features (behavior changes, UI changes)
- Removing features
- Changing user-facing behavior (keyboard shortcuts, gestures, navigation)
- Adding or modifying external integrations (Shortcuts, App Intents, etc.)

Do NOT update for:
- Internal refactoring with no user-visible changes
- Code style improvements
- Bug fixes that restore intended behavior (unless behavior was undocumented)
- Performance optimizations with no feature changes

### How to Update

1. Read the current specification: `Docs/SPECIFICATION.md`
2. Identify the relevant section(s) that need updates
3. Make precise changes that:
   - Describe WHAT the feature does (user perspective)
   - Include UI/UX details (button names, colors, layouts)
   - Document any special behaviors or edge cases
   - Follow the existing structure and style

### Reminder System

After completing any feature implementation or modification:
1. Ask yourself: "Does this change affect what users can do or see?"
2. If YES → Update `Docs/SPECIFICATION.md`
3. If NO → Document in comments/commit message why spec wasn't updated
