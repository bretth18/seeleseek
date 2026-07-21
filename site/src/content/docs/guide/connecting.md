---
title: Connect to the Network
description: Connect to the Soulseek network, log in, and monitor the connection status.
order: 2
section: guide
---

## Log In

When you start seeleseek, the login screen shows:

1. Enter your **username** and **password**.
2. Optional: select **Remember me** to keep your credentials on this Mac.
3. Click **Connect**, or press Enter.

seeleseek connects to the official Soulseek server at `server.slsknet.org`, port `2242`.

## Connection States

The toolbar shows the connection status:

- **Disconnected** — There is no connection. The login screen shows.
- **Connecting** — The app opens a connection to the server. The connect button shows a spinner.
- **Connected** — You are logged in. The main interface shows.
- **Reconnecting** — The connection stopped unexpectedly. seeleseek tries to connect again automatically.
- **Error** — An error occurred. The login screen shows an error message.

## Automatic Reconnection

If the connection stops unexpectedly, seeleseek connects again automatically. The interval between tries increases each time. No action is necessary.

If a different client logs in with your credentials, the server disconnects you with a "Relogged" message. In this condition, seeleseek does not connect again automatically. This prevents a login loop between the two clients.

## Disconnect

To disconnect manually, do one of these steps:

- Select **Connection > Disconnect** in the menu bar.
- Press **⌘⇧D**.

## Network Configuration

seeleseek listens for incoming peer connections on port **2234** by default. You can change the port in Settings > Network.

**UPnP** is on by default. With UPnP, seeleseek configures the port forwarding on your router automatically. If UPnP is not available, seeleseek uses firewall piercing (NAT traversal) to connect to other peers. Manual port forwarding is usually not necessary.

## Menu Bar

If **Show in menu bar** is on in Settings > General, seeleseek adds an icon to the menu bar. The icon menu has these functions:

- **Open** — Opens the main window.
- **Quit** — Stops the app.

The icon stays in the menu bar when you close the main window.
