---
title: Downloads & Transfers
description: Managing downloads, uploads, and transfer queues in seeleseek.
order: 4
section: guide
---

## Transfers View

Navigate to **Transfers** (⌘3) to see all your active, queued, and completed transfers. The view has three tabs: **Downloads**, **Uploads**, and **History**.

The header shows real-time stats:
- **Download speed** (blue arrow)
- **Upload speed** (green arrow)
- **Slots summary** when uploading (e.g., "3 active · Queue: 12")

## Downloads

### Starting a Download

You can start downloads from:
- **Search results** — double-click a result, or right-click and choose Download
- **Browse view** — download individual files or folders from a user's shares
- **Wishlists** — download results from automatic wishlist searches

### Download States

| Status | Icon | Meaning |
|--------|------|---------|
| Queued | ⏳ | Waiting in the remote user's upload queue |
| Connecting | ⟳ | Establishing a peer connection |
| Transferring | ⟳ | Actively downloading with a progress bar |
| Completed | ✓ | Download finished successfully |
| Failed | ✗ | Something went wrong (error shown) |
| Waiting | ⏸ | Paused or waiting for a slot |

### Queue Positions

When a remote user has a full upload queue, your download waits in line. The queue position is shown next to the transfer — seeleseek automatically starts the download when your turn comes.

### Download Actions

Hover over a download to reveal action buttons:
- **Play** — preview completed audio files (30-second limit)
- **Tags** — edit metadata for completed audio files
- **Reveal** — open the file in Finder
- **Cancel** — cancel an active transfer
- **Retry** — retry a failed transfer
- **Remove** — remove from the list

Right-click for more options including "Move to Top" and "Move to Bottom" to reorder the queue.

### Clearing Transfers

Use the **Clear** menu in the header to:
- **Clear Completed** — remove all finished downloads
- **Clear Failed** — remove all errored downloads

## Uploads

The Uploads tab shows files being sent to other users. Uploads happen automatically when another user requests a file you're sharing.

Upload slots are limited — by default, seeleseek allows 5 simultaneous uploads. Additional requests are queued.

## History

The History tab logs all completed and failed transfers with timestamps. It also shows lifetime totals:
- **Total downloaded** — cumulative bytes received
- **Total uploaded** — cumulative bytes sent

## Download Settings

Configure downloads in **Settings > General > Downloads**:

### Download Location

Set where files are saved. Default: `~/Downloads/seeleseek/`.

There's also a separate location for **incomplete files** — partially-downloaded files are stored here until they finish.

### Folder Organization

Choose how downloaded files are organized:

| Template | Example |
|----------|---------|
| Username / Full Path | `alice/Music/Artist/Album/track.flac` |
| Full Path | `Music/Artist/Album/track.flac` |
| Artist - Album | `Artist - Album/track.flac` |
| Filename Only | `track.flac` |
| Custom | Your own template using tokens |

Available tokens for custom templates: `{username}`, `{folders}`, `{artist}`, `{album}`, `{filename}`.

### Transfer Slots

In **Settings > Network > Transfer Slots**:
- **Max Download Slots**: 1–20 (default: 5)
- **Max Upload Slots**: 1–20 (default: 5)

### Speed Limits

In **Settings > Network > Speed Limits**:
- **Upload Limit**: KB/s (0 = unlimited)
- **Download Limit**: KB/s (0 = unlimited)

## Metadata

seeleseek can automatically fetch and apply metadata to downloaded audio files. Configure in **Settings > Metadata**:

- **Fetch metadata automatically** — look up track info after download
- **Fetch album art** — download cover art
- **Embed album art in files** — write art into the audio file's tags
- **Set album art as folder icon** — use cover art as the macOS folder icon

You can also enable **automatic file organization** which renames and moves files based on their metadata using a pattern like `{artist}/{album}/{track} - {title}`.
