---
title: Sharing Files
description: How to configure shared folders and contribute to the Soulseek network.
order: 5
section: guide
---

## Why Share?

Soulseek is a peer-to-peer network — it works best when everyone contributes. Sharing files helps the community and may improve your download priority with other users. Some users enable **leech detection** and will block or deprioritize users who don't share anything.

## Setting Up Shares

1. Open **Settings** (⌘9)
2. Navigate to the **Shares** tab
3. Click **Add Folder** to open the file picker
4. Select one or more folders to share
5. seeleseek scans and indexes the files automatically

The Shares tab shows a summary at the top:
- **Total Folders** shared
- **Total Files** indexed
- **Total Size** of all shared content

Each shared folder displays its name, path, file count, and total size.

## Managing Shared Folders

- **Remove** a folder by clicking the red minus button next to it
- **Rescan** all folders manually with the Rescan button
- Files are indexed with metadata like filename, size, bitrate, and duration

## Share Options

- **Rescan on startup** — automatically re-index shared folders when seeleseek launches (enabled by default)
- **Share hidden files** — include files starting with `.` in your shares (disabled by default)

## How Others See Your Shares

When another user browses your files (via right-click > Browse User on a search result), they see a tree view of your shared folders and files. They can download individual files or entire folders from your shares.

## Share Counts

seeleseek reports your share counts (number of files and folders) to the server. Other users can see this information in your profile, and the network uses it for things like leech detection.

Your share counts update automatically when you add, remove, or rescan folders.

## Privacy Settings

In **Settings > Privacy**, you can control who interacts with your shares:

- **Allow users to browse my files** — when disabled, other users can't browse your shared folder tree (but can still download files they find via search)
- **Respond to search requests** — when disabled, your files won't appear in other users' search results
- **Min query length** — minimum number of characters in a search query before you'll respond (default: 3)
- **Max results per response** — maximum files to return per search query (default: 50)
