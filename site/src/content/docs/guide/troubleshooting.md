---
title: Troubleshooting
description: Solutions for usual problems with connections, downloads, and network configuration.
order: 7
section: guide
---

## Connection Problems

### No connection to the server

1. Make sure that your internet connection operates. Open a different website as a test.
2. Make sure that your username and password are correct.
3. The Soulseek server (`server.slsknet.org:2242`) is possibly not available. The server stops for maintenance at times. Try again after some minutes.
4. Make sure that the macOS firewall does not block seeleseek. Look at **System Settings > Network > Firewall**.

### "Relogged" disconnect

A different Soulseek client logged in with your credentials. Only one client can connect to an account at a time. If a different Soulseek client operates (for example, Nicotine+ or the official Windows client), stop that client first.

seeleseek does not connect again automatically after a relogged disconnect. This prevents a login loop.

### The connection stops frequently

If the connection stops frequently:

- Make sure that your network is stable.
- seeleseek sends a keepalive ping every 5 minutes to keep the connection open.
- The app connects again automatically after temporary stops.

## Search Problems

### No search results

- Make sure that you are connected. Look at the status indicator.
- Use more general search terms. The network searches filenames, not metadata.
- Your query is possibly too short. Some users set a minimum query length.
- The server blocks some phrases. Make sure that your query does not contain a blocked term.

### Slow results

Results arrive when other users respond. This can take some seconds. Results from users with free slots usually arrive faster.

### The result limit

By default, seeleseek stops the collection of results at 500. Change this limit in **Settings > General > Max Results**. Set the value to 0 for no limit.

## Download Problems

### A download stays in the queue

The upload queue of the remote user is full. Your position shows adjacent to the transfer. seeleseek starts the download automatically when you are at the front of the queue. No action is necessary.

### Downloads fail immediately

Usual causes:

- The remote user went offline.
- The file is not in the shares of the user.
- The remote user blocks you (a possible cause is leech detection).
- The network configuration prevents a direct connection.

### Slow transfers

The transfer speed is a function of your connection, and of the upload speed and limits of the remote user. seeleseek shows the transfer rate for each download in real time.

### "Upload Denied" errors

The remote user denied your download request. Possible causes:

- You do not share a sufficient number of files (leech detection).
- You are on the block list of the user.
- The user permits downloads only for some users.

## Share and Upload Problems

### Other users cannot browse my files

1. Make sure that **Allow users to browse my files** is on in Settings > Privacy.
2. Make sure that shared folders are configured in Settings > Shares.
3. Set UPnP to on, or configure port forwarding for port 2234 on your router.

### Users report that downloads from me fail

1. Make sure that free upload slots are available. The Transfers > Uploads tab shows the active uploads.
2. Make sure that the shared folders are accessible and that the files exist.
3. Make sure that **Respond to search requests** is on in Settings > Privacy.
4. If your NAT blocks incoming connections, configure port forwarding for your listen port.

## Network and Firewall

### NAT traversal (firewall piercing)

seeleseek does NAT traversal (firewall piercing) automatically. When a direct connection is not possible:

1. seeleseek asks the server to tell the peer to connect to you.
2. If this fails, the app tries a "pierce firewall" connection.
3. The two peers try to connect at the same time. The first connection that opens wins.

This procedure operates in most network configurations. Manual setup is not necessary.

### Manual port forwarding

If automatic NAT traversal does not operate:

1. Find your listen port in **Settings > Network**. The default is 2234.
2. Log in to the admin panel of your router.
3. Make a port forwarding rule: external port 2234 → the local IP of your Mac, port 2234, TCP.
4. Make sure that the macOS firewall permits incoming connections for seeleseek.

### UPnP

When UPnP is on (the default), seeleseek configures the port forwarding on your router automatically. Not all routers have UPnP. If UPnP fails, seeleseek uses NAT traversal.

## More Tools

For more data, open the **Diagnostics** tab in Settings and the **Network Monitor** view (⌘8).

The Network Monitor shows:

- All active peer connections, with their state, speed, and traffic
- Connection pool statistics
- Speed history graphs
- The geographic distribution of the peers

For protocol-level problems, see the [Protocol Reference](/docs/package/protocol-reference).
