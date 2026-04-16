---
title: Settings & Configuration
description: Complete reference for all seeleseek settings and configuration options.
order: 6
section: guide
---

## Accessing Settings

Open Settings with **⌘9** or from the sidebar. Settings are organized into tabs on the left sidebar.

## Profile

Configure your user profile that other users see when they view your info:
- Profile description text
- Profile picture
- Your buddy count and shared file count are shown automatically

## General

### Downloads
- **Download Location** — where completed files are saved
- **Incomplete Files** — where partial downloads are stored
- **Folder Structure** — how files are organized (see [Downloads & Transfers](/docs/guide/transfers))

### Search
- **Max Results** — stop collecting after this many results; 0 = unlimited (default: 500)

### Startup
- **Launch at login** — start seeleseek when you log into macOS
- **Show in menu bar** — add a persistent menu bar icon (default: on)

## Network

### Connection
- **Listen Port** — port for incoming peer connections; range 1024–65535 (default: 2234)
- **Enable UPnP** — automatic router port forwarding (default: on)

### Transfer Slots
- **Max Download Slots** — simultaneous downloads; 1–20 (default: 5)
- **Max Upload Slots** — simultaneous uploads; 1–20 (default: 5)

### Speed Limits
- **Upload Limit** — KB/s; 0 = unlimited (default: 0)
- **Download Limit** — KB/s; 0 = unlimited (default: 0)

## Shares

See [Sharing Files](/docs/guide/sharing) for details on configuring shared folders.

## Metadata

### Auto-fetch
- **Fetch metadata automatically** — look up track info after download (default: on)
- **Fetch album art** — download cover art (default: on)
- **Embed album art in files** — write art into audio tags (default: on)
- **Set album art as folder icon** — macOS folder icon (default: on)

### Organization
- **Organize downloads automatically** — rename/move files by metadata (default: off)
- **Pattern** — template for organization, e.g., `{artist}/{album}/{track} - {title}`
- Available tokens: `{artist}`, `{album}`, `{track}`, `{title}`, `{year}`

## Chat

- **Show join/leave messages** — display when users enter/leave rooms (default: on)

## Notifications

### General
- **Enable notifications** — show macOS notifications (default: on)
- **Play notification sound** — audible alert (default: on)
- **Only when app is in background** — suppress when seeleseek is focused (default: off)
- **Notification sound** — choose from 15 macOS sounds (Default, Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink)

### Notify me about
- **Download completed** (default: on)
- **Upload completed** (default: off)
- **Private messages** (default: on)

## Privacy

### Visibility
- **Show online status** — appear as online to other users (default: on)
- **Allow users to browse my files** — let others see your share tree (default: on)

### Search Responses
- **Respond to search requests** — your files appear in others' searches (default: on)
- **Min query length** — 1–20 characters (default: 3)
- **Max results per response** — 0–500 (default: 50)

### Blocklist
Block specific users by username with an optional reason. Blocked users can't interact with you. You can view and manage blocked users in the list below.

### Leech Detection
Detect users who download without sharing:
- **Enable Leech Detection** — monitor downloaders' share counts
- **Minimum shared files** — threshold (default: 0)
- **Minimum shared folders** — threshold (default: 0)
- **Action** — Do nothing, Send message, Block user, or Send message and block
- **Custom message** — template message sent to detected leeches

## Diagnostics

Access diagnostic tools and logs for troubleshooting connection and transfer issues.

## Update

Check for and install seeleseek updates.

## About

View version information, credits, and links.
