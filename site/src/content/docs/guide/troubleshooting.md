---
title: Troubleshooting
description: Solutions for common issues with connections, downloads, and network configuration.
order: 7
section: guide
---

## Connection Issues

### Can't connect to server

1. **Check your internet connection** — make sure you can reach other websites
2. **Verify credentials** — ensure your username and password are correct
3. **Server may be down** — the Soulseek server (`server.slsknet.org:2242`) occasionally goes offline for maintenance. Try again in a few minutes.
4. **Firewall** — make sure macOS isn't blocking seeleseek. Check **System Settings > Network > Firewall**.

### "Relogged" disconnect

This means another Soulseek client logged in with your credentials. Only one client can be connected per account at a time. If you're running another Soulseek client (like Nicotine+ or the official Windows client), close it first.

Auto-reconnect is intentionally disabled for relogged disconnects to prevent a login loop.

### Connection keeps dropping

If you're experiencing frequent disconnects:
- Check if your network is stable
- seeleseek sends keepalive pings every 5 minutes to maintain the connection
- Auto-reconnect will handle temporary drops automatically

## Search Issues

### No search results

- Make sure you're connected (check the status indicator)
- Try broader search terms — the network searches filenames, not metadata
- Your search may be too short. Some users have a minimum query length setting.
- The server filters certain phrases — check if your query contains restricted terms

### Results are slow

Search results arrive as other users respond, which can take several seconds. Results from users who are online and have free slots tend to arrive faster.

### Max results limit

By default, seeleseek stops collecting after 500 results. Change this in **Settings > General > Max Results** (set to 0 for unlimited).

## Download Problems

### Downloads stuck in queue

This means the remote user's upload queue is full. Your position is shown next to the transfer. seeleseek will automatically start the download when your turn comes — just leave it running.

### Downloads fail immediately

Common causes:
- The remote user went offline
- The file was removed from their shares
- You're blocked by the remote user (possibly leech detection)
- Network configuration prevents a direct connection

### Slow transfers

Transfer speed depends on both your connection and the remote user's upload speed and limits. seeleseek shows the real-time transfer rate for each download.

### "Upload Denied" errors

The remote user has denied your download request. Possible reasons:
- You're not sharing enough files (leech detection)
- You're on their block list
- They have restricted downloads to certain users

## Sharing & Upload Issues

### Other users can't browse my files

1. Make sure **Allow users to browse my files** is enabled in Settings > Privacy
2. Check that you have shared folders configured in Settings > Shares
3. Try enabling UPnP or manually forwarding port 2234 on your router

### Users say they can't download from me

1. Check your upload slots aren't full — the Transfers > Uploads tab shows active uploads
2. Verify your shared folders are accessible and the files still exist
3. Make sure **Respond to search requests** is enabled in Settings > Privacy
4. If behind a strict NAT, try port forwarding your listen port

## Network & Firewall

### NAT traversal / firewall piercing

seeleseek supports automatic NAT traversal (firewall piercing). When a direct connection can't be established:

1. seeleseek asks the server to tell the peer to connect to us
2. If that fails, it attempts a "pierce firewall" connection
3. Both peers race to establish a connection

This works in most network configurations without any manual setup.

### Manual port forwarding

If automatic NAT traversal isn't working:

1. Note your listen port in **Settings > Network** (default: 2234)
2. Log into your router's admin panel
3. Create a port forwarding rule: external port 2234 → your Mac's local IP, port 2234, TCP
4. Make sure macOS Firewall allows incoming connections for seeleseek

### UPnP

When UPnP is enabled (default), seeleseek will attempt to automatically configure port forwarding on your router. Not all routers support UPnP. If it fails, seeleseek falls back to NAT traversal.

## Advanced Troubleshooting

For deeper investigation, check the **Diagnostics** tab in Settings and the **Network Monitor** view (⌘8).

The Network Monitor shows:
- All active peer connections with their state, speed, and traffic
- Connection pool statistics
- Speed history graphs
- Geographic distribution of peers

If you're experiencing issues related to the underlying protocol, see the [Protocol Reference](/docs/package/protocol-reference) for technical details.
