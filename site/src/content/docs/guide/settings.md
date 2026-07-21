---
title: Settings
description: A reference for all seeleseek settings and configuration options.
order: 6
section: guide
---

## Open the Settings

Press **⌘9**, or use the sidebar. The settings show in tabs on the left sidebar.

## Profile

Configure the profile that other users see:

- The profile description text
- The profile picture
- The app shows your buddy count and your shared file count automatically

## General

### Downloads
- **Download Location** — The folder for completed files.
- **Incomplete Files** — The folder for partial downloads.
- **Folder Structure** — The structure for downloaded files. See [Downloads and Transfers](/docs/guide/transfers).

### Search
- **Max Results** — The app stops the collection of results at this limit. 0 is no limit. The default is 500.

### Startup
- **Launch at login** — Starts seeleseek when you log in to macOS.
- **Show in menu bar** — Adds an icon to the menu bar. The default is on.

## Network

### Connection
- **Listen Port** — The port for incoming peer connections. The range is 1024 to 65535. The default is 2234.
- **Enable UPnP** — Configures the router port forwarding automatically. The default is on.

### Transfer Slots
- **Max Download Slots** — The number of parallel downloads. 1 to 20. The default is 5.
- **Max Upload Slots** — The number of parallel uploads. 1 to 20. The default is 5.

### Speed Limits
- **Upload Limit** — KB/s. 0 is no limit. The default is 0.
- **Download Limit** — KB/s. 0 is no limit. The default is 0.

## Shares

See [Share Files](/docs/guide/sharing) for the configuration of shared folders.

## Metadata

### Auto-fetch
- **Fetch metadata automatically** — Gets the track data after a download. The default is on.
- **Fetch album art** — Downloads the cover art. The default is on.
- **Embed album art in files** — Writes the art into the audio tags. The default is on.
- **Set album art as folder icon** — Sets the macOS folder icon. The default is on.

### Organization
- **Organize downloads automatically** — Renames and moves files by their metadata. The default is off.
- **Pattern** — The template for the organization, for example `{artist}/{album}/{track} - {title}`.
- These tokens are available: `{artist}`, `{album}`, `{track}`, `{title}`, `{year}`.

## Chat

- **Show join/leave messages** — Shows a message when a user comes into a room or goes out of a room. The default is on.

## Notifications

### General
- **Enable notifications** — Shows macOS notifications. The default is on.
- **Play notification sound** — Plays a sound with each notification. The default is on.
- **Only when app is in background** — Stops notifications when seeleseek is the active app. The default is off.
- **Notification sound** — A selection of 15 macOS sounds (Default, Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink).

### Notification Events
- **Download completed** — The default is on.
- **Upload completed** — The default is off.
- **Private messages** — The default is on.

## Privacy

### Visibility
- **Show online status** — Other users see you as online. The default is on.
- **Allow users to browse my files** — Other users can see your share tree. The default is on.

### Search Responses
- **Respond to search requests** — Your files show in the searches of other users. The default is on.
- **Min query length** — 1 to 20 characters. The default is 3.
- **Max results per response** — 0 to 500. The default is 50.

### Blocklist
Block users by username. A reason is optional. A blocked user cannot interact with you. The list below the controls shows the blocked users. You can manage the list there.

### Leech Detection
This function finds users who download files but do not share files:

- **Enable Leech Detection** — Monitors the share counts of users who download from you.
- **Minimum shared files** — The minimum number of shared files. The default is 0.
- **Minimum shared folders** — The minimum number of shared folders. The default is 0.
- **Action** — Do nothing, Send message, Block user, or Send message and block.
- **Custom message** — The message template that the app sends to these users.

## Diagnostics

This tab has diagnostic tools and logs. Use them to find the causes of connection and transfer problems.

## Update

Find and install seeleseek updates.

## About

This tab shows the version, the credits, and links.
