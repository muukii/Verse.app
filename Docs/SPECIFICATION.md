# YouTubeSubtitle - Product Specification

## Overview

YouTubeSubtitle is a macOS/iOS application that allows users to watch YouTube videos with subtitles displayed alongside. It features tap-to-jump navigation, auto-scrolling subtitles, and watch history management.

### Target Users
- Language learners (e.g., English learners)
- Users who want to understand content precisely while reading subtitles
- Users who want to repeatedly watch specific sections

## Core Features

### 1. Video Playback

#### 1.1 YouTube Video Playback
- Play videos from YouTube URLs
- Support for play/pause and seek operations
- Supported URL formats:
  - `https://www.youtube.com/watch?v=VIDEO_ID`
  - `https://youtu.be/VIDEO_ID`

#### 1.2 Playback Controls
- **Time Display**: Current time / Total duration
- **Seek Bar**: Drag to jump to any position
- **Playback Speed**: 0.25x - 2.0x (0.25 increments)
- **Loop/Repeat**:
  - Set start and end times
  - Repeat playback of specified section
- **Step Mode**:
  - Pauses playback at each subtitle cue's end (for language learning)
  - Toggle via context menu on play button (Normal / Step Mode)
  - Behavior: Auto-stop at each cue's `endTime` → tap play to continue to next cue
  - Visual indicator: Outline icons (`play`/`pause`) in step mode, filled icons (`play.fill`/`pause.fill`) in normal mode
  - Setting persisted via `@AppStorage`

### 2. Subtitle Features

#### 2.1 Subtitle Retrieval and Display
- **Supported Languages**: English subtitles
- **Display Format**: Timestamp + subtitle text
- **Auto-fetch**: Subtitles are automatically retrieved when opening a video

#### 2.2 Subtitle Navigation
- **Tap to Jump**: Tap a subtitle to seek to that timestamp
- **Current Subtitle Highlight**: Currently playing subtitle highlighted in blue
- **Auto-scroll (Tracking)**:
  - Enabled by default
  - Subtitles automatically scroll to follow playback position

#### 2.3 Subtitle Tracking Control
- **Toggle Button**: "eye" / "eye.slash" icon in header
- **Auto-disable**: Automatically turns off when user manually scrolls
- **Manual Enable**: Tap button to re-enable tracking

### 3. Watch History

#### 3.1 History Management
- **Auto-save**: Automatically added to history when opening a video
- **Duplicate Prevention**: Only keeps the most recent entry for each video
- **Maximum Entries**: 50 (oldest entries auto-deleted)
- **Data Storage**: Stored locally on device

#### 3.2 History Display
- **List Format**: Thumbnail + Title + Timestamp
- **Thumbnail**: Video thumbnail image (120x68px)
- **Title**: Auto-fetched video title
- **Relative Time**: "2 hours ago", "1 day ago", etc.

#### 3.3 History Operations
- **Tap to Play**: Tap history item to open video
- **Swipe to Delete**: Delete individual items
- **Clear All**: "Clear History" button in toolbar

### 4. External Integration

#### 4.1 Shortcuts Support
- **Shortcuts App**: "Open YouTube Video" action available
- **Siri Support**: Voice command activation
- **URL Reception**: Receive YouTube URLs from Shortcuts or other apps

## Screen Layout

### Home Screen (HomeView)
- **URL Input Field**: Enter YouTube URL
- **Watch History List**:
  - Thumbnail image
  - Video title
  - Watch time (relative display)
- **Operations**:
  - Press Enter after URL input to open video
  - Tap history item to open video
  - Swipe to delete individual items
  - Clear all from toolbar

### Player Screen (PlayerView)
- **Left Side: Video Player**
  - YouTube player
  - Playback controls (play/pause, seek bar)
  - Playback speed adjustment
  - Loop settings
- **Right Side: Subtitle Panel**
  - Header (subtitle count, tracking button)
  - Subtitle list (scrollable)
  - Current subtitle highlighted

## UI/UX Specifications

### Colors
- **Current Subtitle**: Blue background highlight
- **Normal Subtitle**: Light gray background
- **Tracking ON**: Blue icon
- **Tracking OFF**: Gray icon

### Layout
- **HomeView**: Vertical layout (input at top, list below)
- **PlayerView**: Horizontal 2-column layout
- **Subtitle Panel Width**: Fixed or variable

## Future Enhancements

- [ ] Display author/channel name (not supported by YouTubeKit)
- [ ] Subtitle language selection
- [ ] Playlist support
- [ ] Offline subtitle storage
- [ ] Subtitle search functionality
- [ ] Enhanced dark mode support
