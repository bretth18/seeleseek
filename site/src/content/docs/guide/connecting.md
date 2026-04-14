---
title: Connecting
description: How to connect to the Soulseek network, manage your login, and understand connection states.
order: 2
section: guide
---

## Logging In

When you launch seeleseek, you'll see the login screen:

1. Enter your **username** and **password**
2. Optionally check **Remember me** to save your credentials locally
3. Click **Connect** (or press Enter)

seeleseek connects to the official Soulseek server at `server.slsknet.org` on port `2242`.

## Connection States

The app shows your connection status in the toolbar:

- **Disconnected** — Not connected. The login screen is shown.
- **Connecting** — Establishing a connection to the server. The connect button shows a spinner.
- **Connected** — Logged in and ready. The main app interface is shown.
- **Reconnecting** — The connection dropped unexpectedly. seeleseek will automatically try to reconnect with exponential backoff.
- **Error** — Something went wrong. An error message is shown on the login screen.

## Auto-Reconnect

If your connection drops unexpectedly (network hiccup, server restart, etc.), seeleseek will automatically try to reconnect. You don't need to do anything — just wait for it to re-establish the connection.

If another client logs in with your credentials, you'll be disconnected with a "Relogged" message. In this case, auto-reconnect is disabled to avoid a login loop.

## Disconnecting

To disconnect manually:

- Use **Connection > Disconnect** in the menu bar
- Or press **⌘⇧D**

## Network Configuration

seeleseek listens for incoming peer connections on port **2234** by default. You can change this in Settings > Network.

**UPnP** is enabled by default, which means seeleseek will attempt to automatically configure your router's port forwarding. If UPnP isn't available, seeleseek uses **firewall piercing** (NAT traversal) to establish connections with other peers — no manual port forwarding required in most cases.

## Menu Bar

If **Show in menu bar** is enabled in Settings > General, seeleseek adds a menu bar icon that lets you:

- **Open** the main window
- **Quit** the app

The menu bar icon stays active even when you close the main window.
