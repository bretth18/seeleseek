---
title: Share Files
description: Configure shared folders and give files to the Soulseek network.
order: 5
section: guide
---

## Why Share?

Soulseek is a peer-to-peer network. The network operates best when all users share files. Shared files help the community. They can also increase your download priority with other users. Some users have leech detection on. These users can block users who do not share files.

## Add Shared Folders

1. Open **Settings** (⌘9).
2. Go to the **Shares** tab.
3. Click **Add Folder** to open the file picker.
4. Select one or more folders.
5. seeleseek scans the files and makes an index automatically.

The top of the Shares tab shows a summary:

- **Total Folders** — the number of shared folders
- **Total Files** — the number of files in the index
- **Total Size** — the size of all shared content

Each shared folder shows its name, path, file count, and total size.

## Manage Shared Folders

- To remove a folder, click the red minus button adjacent to it.
- To scan all folders again, click the **Rescan** button.
- The index keeps metadata for each file: the filename, size, bitrate, and duration.

## Share Options

- **Rescan on startup** — The app scans the shared folders again at each start. The default is on.
- **Share hidden files** — The shares include files with names that start with `.`. The default is off.

## Your Shares as Other Users See Them

A user can browse your files. (Right-click a search result, then select Browse User.) The user sees a tree view of your shared folders and files. The user can download single files or full folders.

## Share Counts

seeleseek sends your share counts (the number of files and folders) to the server. Other users can see this data in your profile. The network uses the data for functions such as leech detection.

The share counts change automatically when you add, remove, or scan folders.

## Privacy Settings

In **Settings > Privacy**, you can control the access to your shares:

- **Allow users to browse my files** — When this is off, other users cannot browse your folder tree. They can download files that they find with a search.
- **Respond to search requests** — When this is off, your files do not show in the search results of other users.
- **Min query length** — The minimum number of characters in a query before the app sends a response. The default is 3.
- **Max results per response** — The maximum number of files in a response to one query. The default is 50.
