---
title: Downloads and Transfers
description: Control downloads, uploads, and transfer queues in seeleseek.
order: 4
section: guide
---

## Transfers View

Go to **Transfers** (⌘3) to see the active, queued, and completed transfers. The view has three tabs: **Downloads**, **Uploads**, and **History**.

The header shows this data in real time:

- **Download speed** (blue arrow)
- **Upload speed** (green arrow)
- **Slot summary** during uploads, for example "3 active · Queue: 12"

## Downloads

### Start a Download

You can start downloads from these locations:

- **Search results** — Double-click a result. Or right-click a result and select Download.
- **Browse view** — Download files or folders from the shares of a user.
- **Wishlists** — Download results from automatic wishlist searches.

### Download States

| Status | Icon | Meaning |
|--------|------|---------|
| Queued | ⏳ | The download is in the upload queue of the remote user |
| Connecting | ⟳ | The app opens a peer connection |
| Transferring | ⟳ | The download is in progress. A progress bar shows |
| Completed | ✓ | The download is complete |
| Failed | ✗ | An error occurred. The error shows |
| Waiting | ⏸ | The download is on hold, or waits for a slot |

### Queue Positions

If the upload queue of the remote user is full, your download stays in the queue. The queue position shows adjacent to the transfer. seeleseek starts the download automatically when you are at the front of the queue.

### Download Actions

Move the pointer over a download to show the action buttons:

- **Play** — Plays the first 30 seconds of a completed audio file.
- **Tags** — Opens the metadata editor for a completed audio file.
- **Reveal** — Shows the file in the Finder.
- **Cancel** — Stops an active transfer.
- **Retry** — Starts a failed transfer again.
- **Remove** — Removes the transfer from the list.

Right-click a download for more functions. **Move to Top** and **Move to Bottom** change the sequence of the queue.

### Remove Transfers from the List

Use the **Clear** menu in the header:

- **Clear Completed** — Removes all completed downloads.
- **Clear Failed** — Removes all failed downloads.

## Uploads

The Uploads tab shows the files that the app sends to other users. An upload starts automatically when a user requests a file from your shares.

The number of upload slots has a limit. By default, seeleseek permits 5 uploads at the same time. Requests above this limit go into the queue.

## History

The History tab shows all completed and failed transfers, with timestamps. It also shows these totals:

- **Total downloaded** — All bytes received.
- **Total uploaded** — All bytes sent.

## Download Settings

Configure downloads in **Settings > General > Downloads**:

### Download Location

Set the folder for completed files. The default is `~/Downloads/seeleseek/`.

A different folder holds the **incomplete files**. The app keeps a download there until the download is complete.

### Folder Structure

Select the structure for downloaded files:

| Template | Example |
|----------|---------|
| Username / Full Path | `alice/Music/Artist/Album/track.flac` |
| Full Path | `Music/Artist/Album/track.flac` |
| Artist - Album | `Artist - Album/track.flac` |
| Filename Only | `track.flac` |
| Custom | A template that you make with tokens |

These tokens are available for custom templates: `{username}`, `{folders}`, `{artist}`, `{album}`, `{filename}`.

### Transfer Slots

In **Settings > Network > Transfer Slots**:

- **Max Download Slots** — 1 to 20. The default is 5.
- **Max Upload Slots** — 1 to 20. The default is 5.

### Speed Limits

In **Settings > Network > Speed Limits**:

- **Upload Limit** — KB/s. 0 is no limit.
- **Download Limit** — KB/s. 0 is no limit.

## Metadata

seeleseek can get and apply metadata for downloaded audio files automatically. Configure this function in **Settings > Metadata**:

- **Fetch metadata automatically** — Gets the track data after a download.
- **Fetch album art** — Downloads the cover art.
- **Embed album art in files** — Writes the art into the tags of the audio file.
- **Set album art as folder icon** — Uses the cover art as the macOS folder icon.

The app can also organize files automatically. This function renames and moves files by their metadata. It uses a pattern, for example `{artist}/{album}/{track} - {title}`.
