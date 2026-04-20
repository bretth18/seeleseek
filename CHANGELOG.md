# Changelog

## Unreleased

### Package (`SeeleseekCore`) — breaking API changes

Consumers of `SeeleseekCore` outside the app target must update to these new
signatures. The app target in this repo is updated in the same diff.

- **`NetworkClient.onTransferResponse`** — signature gained a `reason: String?`
  parameter. The peer's rejection reason string was previously parsed but
  dropped on the floor; consumers can now distinguish "Queued", "Cancelled",
  etc. from a generic failure.
  ```swift
  // Before
  var onTransferResponse: ((UInt32, Bool, UInt64?, PeerConnection) async -> Void)?
  // After
  var onTransferResponse: ((UInt32, Bool, UInt64?, String?, PeerConnection) async -> Void)?
  //                                            ^^^^^^^ reason
  ```
  App-side `UploadManager.handleTransferResponse` now maps `"Queued"` →
  `Transfer.TransferStatus.queued`, `"Cancelled"` → `.cancelled`, everything
  else → `.failed`. If you were pattern-matching `.failed` to detect
  rejections, widen the check.

- **`PeerConnectionEvent.transferResponse`** — same `reason: String?` addition.
- **`PeerPoolEvent.transferResponse`** — same `reason: String?` addition.

- **`MessageParser.parseRoomList`** — return type changed from
  `[RoomListEntry]?` to `RoomListInfo?`, which carries four sections:
  `publicRooms`, `ownedPrivate`, `memberPrivate`, `operatedPrivate`. Old
  consumers read only the first section; the inline handler always parsed all
  four but kept the data local. Update call sites:
  ```swift
  // Before
  let rooms: [RoomListEntry]? = MessageParser.parseRoomList(payload)
  // After
  let info: RoomListInfo? = MessageParser.parseRoomList(payload)
  let publicRooms = info?.publicRooms ?? []
  ```

- **`MessageParser.PrivateMessageInfo.isAdmin`** → **`isNewMessage`**. The
  trailing bool in the wire format is the spec's "new message" flag (true for
  live delivery, false for a server replay to a previously-offline recipient).
  The old name was a semantic bug in the dead parser path; no production code
  read it, but any test or external code that did needs to rename.

- **`MessageParser.WatchUserInfo.countryCode: String?`** — new field. The
  trailing country-code string (present when status is online or away per
  spec) was previously read by the inline handler and dropped. Now exposed
  and seeded into the GeoIP cache so flags light up without a round-trip.

- **`MessageParser.PeerInfo.connectionType: String`** — new field on the
  struct returned by `parseConnectToPeer`. The type tag ("P" / "F" / "D")
  was captured and discarded; now preserved.

- **`MessageParser` struct fields** are now `public let` everywhere, and
  every info struct gained `Equatable` conformance for test ergonomics. This
  is additive — existing read sites keep working.

### Package — behaviour changes (non-breaking)

- **Parsing is now canonical.** Every handler in `ServerMessageHandler` and
  `PeerConnection` that previously parsed a wire payload inline now delegates
  to `MessageParser.parseX`. One parser per message type instead of two.
  Handlers only do side effects. Drift is now hard: adding a second inline
  parser next to an existing `MessageParser.parseX` is visible at review time.

- **`UserInfoReply` picture bytes are no longer dropped.** The inline parser
  previously skipped over the picture-data field. Replies now flow through
  `PeerConnectionEvent.userInfoReply` → `PeerPoolEvent.userInfoReply` →
  `NetworkClient.handleUserInfoReplyEvent` → `addUserInfoHandler` subscribers.

- **`NetworkClient.fetchUserInfo(from:)`** — new public API for soliciting a
  peer's description, picture, and upload stats. Session-cached, concurrent
  callers coalesce. Mirrors the `addUserInfoHandler` multi-listener pattern
  used for `addUserStatusHandler` / `addUserStatsHandler`.

- **`NetworkClient.addUserInfoHandler(_:)`** — new public API for subscribing
  to incoming UserInfoReply events.

- **`NetworkClient.browseUser`** and `fetchUserInfo` now share a single
  `establishPeerConnection(for:forceFresh:)` helper for the ConnectToPeer +
  direct/indirect race dance.

### App

- **Statistics and Network Monitor merged** into one sidebar destination
  named "Activity", with sub-tabs: Overview · Peers · Search · History.
  Removes a duplicated bandwidth chart, three peer list implementations, two
  topology renderers, and a placeholder "Transfers" tab that never read
  `DownloadManager`/`UploadManager`.

- **Profile sheet** now fetches description + picture via UserInfoRequest
  on open. Own-profile view populates from the local `myDescription` /
  `myPicture` directly (the Soulseek protocol has no server-side self-fetch).

- **Activity feed context menu** gained a "Block from Connecting" action
  (via `UserContextMenuItems(showBlock: true)`), routed through the existing
  `SocialState.blockUser` / `unblockUser` APIs.

- **`DemoDataSeeder`** now gated behind `#if DEBUG`. Release builds no
  longer ship the ~288-line demo-data enum; the screenshot capture flow
  still works under Debug (UI tests run in Debug).

### Migration checklist

If you're consuming `SeeleseekCore` from another target:

1. Update any `onTransferResponse` closure to accept the new `reason:
   String?` parameter.
2. Update any `PeerConnectionEvent.transferResponse` / `PeerPoolEvent.transferResponse`
   pattern match to destructure 5 fields instead of 4.
3. Update any `MessageParser.parseRoomList` caller to read `.publicRooms`
   on the returned struct.
4. Rename `PrivateMessageInfo.isAdmin` → `isNewMessage` (and flip the
   default assumption if your code inverted it).
5. Nothing else requires code changes — all additions are source-compatible.
