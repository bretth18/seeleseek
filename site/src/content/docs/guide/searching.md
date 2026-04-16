---
title: Searching for Files
description: How to search the Soulseek network, filter results, and use wishlists.
order: 3
section: guide
---

## Basic Search

1. Navigate to **Search** (⌘1)
2. Type your query in the search bar — it reads "Search or paste a music URL..."
3. Press **Enter** or click the search button

Results stream in from other users on the network as they respond. You'll see a count of results and unique users updating in real time.

## Search History

seeleseek remembers your last 10 searches. Click the dropdown arrow on the search bar to quickly re-run a previous search.

## Multiple Tabs

You can have multiple searches open simultaneously. Each search gets its own tab, so you can compare results from different queries.

## Filtering Results

### Quick Filters

The filter bar above results offers preset filters:

- **MP3 320** — MP3 files at 320 kbps
- **FLAC** — FLAC lossless files
- **Lossless** — Any lossless format (FLAC, WAV, APE, AIFF)
- **Hi-Res** — Files with sample rate above 44.1 kHz or bit depth above 16

An active filter badge shows how many filters are applied.

### Advanced Filters

Expand the full filter panel to filter by:

| Filter | Options |
|--------|---------|
| **Format** | mp3, flac, ogg, m4a, aac, wav, aiff, ape |
| **Bitrate** | Any, 128+, 192+, 256+, 320+ kbps |
| **Sample Rate** | Any, 44.1k+, 48k+, 96k+ |
| **Bit Depth** | Any, 16+, 24+, 32+ |
| **Free Slots** | Only show results from users with available upload slots |

## Understanding Results

Each search result shows:

- **Filename** with a color-coded icon (green for lossless, blue for audio, gray for other)
- **Username** and country flag (when available)
- **Folder path** on the remote user's computer
- **Quality badges** — format, bitrate (color-coded: green for 320+/lossless, blue for 256+, orange for 192+), sample rate, bit depth
- **Duration** and **file size**
- **Slot status** — a green checkmark means the user has free upload slots; an hourglass with a number shows your queue position

### Private Files

Some results show a lock icon — these are private files that the user has restricted. You may not be able to download them.

## Result Actions

- **Click** a result to select it
- **Double-click** to start a download
- **Right-click** for a context menu with more options:
  - Download the file or entire folder
  - Browse the user's shared files
  - View the user's profile
  - Preview album art (for audio files)
  - Ignore/unignore the user
  - Copy the filename or full path

### Bulk Downloads

Click the **Select** button to enter selection mode, where you can check multiple results and download them all at once.

## Wishlists

Wishlists are saved searches that run automatically at regular intervals.

1. Navigate to **Wishlists** (⌘2)
2. Type a search query and click **Add**
3. seeleseek will periodically search for that query in the background

Each wishlist entry shows:
- A star toggle to enable/disable it
- The query text
- When it was last searched
- A result count (expand to see results)
- A manual "search now" button

The server controls the wishlist search interval (typically every few minutes).

## Search Settings

In **Settings > General > Search**:

- **Max Results** — Stop collecting results after this limit. Set to 0 for unlimited. Default: 500.
