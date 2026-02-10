# SeeleSeek View Architecture Refactoring Plan

Audit of all SwiftUI view files across DesignSystem and Features. Prioritized by severity.

---

## Severity Legend

| Level | Meaning |
|-------|---------|
| **P0 - Critical** | Files 3x+ over 150-line limit, networking/business logic embedded in views, untestable |
| **P1 - High** | Files 2x+ over limit, multiple SRP violations, duplicated logic across files |
| **P2 - Medium** | Files modestly over limit, repeated patterns that should be components, state in wrong place |
| **P3 - Low** | Minor organization issues, nice-to-have extractions |

---

## P0 - Critical

### 1. SettingsView.swift (1,354 lines)

The single largest file in the codebase. Contains raw TCP socket code and DNS resolution inside a SwiftUI view.

**Current responsibilities:** 8 section views, network diagnostics with NWConnection/socket APIs, leech detection UI, blocked user management, shared folder picker, all in one file.

| Extract To | Source Lines | What It Does |
|-----------|-------------|--------------|
| `DiagnosticsService.swift` | 1092-1218 | DNS resolution, TCP connection testing - **networking code in a View** |
| `DiagnosticsView.swift` | 816-1219 | Test UI, result display, port reachability |
| `PrivacySettingsView.swift` | 447-814 | Blocklist management, leech detection config |
| `LeechDetectionSettingsView.swift` | ~599-751 | Leech thresholds, actions, detected leeches list |
| `SharesSettingsView.swift` | 226-343 | Shared folder management, rescan UI |
| `GeneralSettingsView.swift` | 108-199 | Download templates, startup options |

**Preview support:** Each extracted view gets `#Preview` with mock `SettingsState()`.

---

### 2. BrowseView.swift (866 lines)

5 view structs in one file. FileTreeRow (219 lines) contains recursive download logic.

| Extract To | Source Lines | What It Does |
|-----------|-------------|--------------|
| `FileTreeRow.swift` | 403-621 | Recursive file tree row with expand/collapse |
| `FileTreeDownloadService` (move logic) | 532-597 | `downloadFile()`, `downloadFolder()`, `collectFiles()` - business logic |
| `SharesVisualizationPanel.swift` | 625-823 | Stats computation, file type charts, bitrate distribution |
| `BrowseTabButton.swift` | 338-401 | Tab button component |
| `BrowseEmptyStates.swift` | 115-224 | 4 repeated empty state patterns -> single parameterized component |
| `BreadcrumbNavigation.swift` | 267-301 | Path breadcrumb bar |

---

### 3. StatisticsView.swift (652 lines)

8 visualization components defined inline with speed percentage calculations in view body.

| Extract To | Source Lines | What It Does |
|-----------|-------------|--------------|
| `SpeedGaugeView.swift` | ~305-350 | Circular speed gauge |
| `SpeedChartView.swift` | ~351-430 | Speed history line chart |
| `ConnectionRingView.swift` | ~431-500 | Connection type ring |
| `TransferRatioView.swift` | ~501-530 | Upload/download ratio display |
| `PeerActivityHeatmap.swift` | ~531-580 | Activity bucketing + grid display |
| `TransferHistoryRow.swift` | ~600-646 | History row component |
| `StatisticsHelpers.swift` | scattered | Speed percentage calcs, time range filtering |

---

### 4. NetworkMonitorView.swift (577 lines)

12+ view components in one file spanning 4 tab contents.

| Extract To | Source Lines | What It Does |
|-----------|-------------|--------------|
| `NetworkOverviewTab.swift` | ~100-250 | Metrics, bandwidth chart, connection health |
| `MetricCard.swift` | private decl | Reusable metric display card |
| `BandwidthChartCard.swift` | private decl | Bandwidth chart component |
| `ConnectionHealthCard.swift` | private decl | Health score display |
| `QuickPeersCard.swift` | private decl | Peer summary list |

---

### 5. ChatView.swift (638 lines)

4 view structs, duplicated status dots, unread badges, and context menus.

| Extract To | Source Lines | What It Does |
|-----------|-------------|--------------|
| `ChatRoomContentView.swift` | ~283-450 | Room messages, ticker, input |
| `PrivateChatContentView.swift` | ~452-500 | DM messages, input |
| `MessageBubble.swift` | ~504-581 | Message display + context menu |
| `MessageInput.swift` | ~585-631 | Text input with send button |
| `ChatSidebar.swift` | ~44-210 | Room list + DM list sidebar |

---

## P1 - High

### 6. StandardComponents.swift (462 lines)

11 unrelated components in one file. Every other view in the app imports from here.

| Extract To | Lines | Component |
|-----------|-------|-----------|
| `StandardEmptyState.swift` | ~54 | Empty state with icon, title, subtitle |
| `StandardSectionHeader.swift` | ~44 | Section header with count |
| `StandardToolbar.swift` | ~50 | 3-zone toolbar |
| `StandardTabBar.swift` | ~70 | Horizontal tab bar with badges |
| `StandardSearchField.swift` | ~55 | Search input with clear button |
| `StandardListRow.swift` | ~35 | Hover-enabled list row |
| `StandardMetadataBadge.swift` | ~30 | Small metadata label |
| `StandardStatBadge.swift` | ~27 | Metric badge |
| `StandardProgressBar.swift` | ~27 | Custom progress bar |
| `StandardStatusDot.swift` | ~23 | Status indicator |

Each file gets its own `#Preview` block.

---

### 7. FileVisualization.swift (441 lines)

6 visualization components + FlowLayout custom Layout.

| Extract To | What |
|-----------|------|
| `FileTreemap.swift` | FileTreemap + TreemapCell |
| `FileTypeDistribution.swift` | Stacked bar + legend |
| `BitrateDistribution.swift` | Bitrate histogram |
| `AudioWaveform.swift` | Animated waveform |
| `SizeComparisonBars.swift` | Comparative bar chart |
| `FlowLayout.swift` | Custom Layout (used across many views) |

---

### 8. TransfersView.swift - Duplicated Code (677 lines)

TransferRow and HistoryRow duplicate audio preview, reveal-in-Finder, and context menus.

| Extract To | What |
|-----------|------|
| `AudioPreviewService.swift` | Shared audio player logic (30-sec preview, play/stop) |
| `UserActionMenu.swift` | Shared context menu: View Profile, Browse Files, Send Message |
| `TransferActionButtons.swift` | Conditional action button strip (play, tag, folder, cancel, retry, remove) |
| `TransferStatusIcon.swift` | Status icon with circle background |
| `HistoryRow.swift` | Move to own file, use shared components |

---

### 9. SearchResultRow.swift (368 lines)

Batch download logic, clipboard operations, and color computation all live in the view.

| Extract To | What |
|-----------|------|
| `SearchResult+Colors.swift` | `bitrateColor`, `sampleRateColor`, `iconColor` as model extensions |
| `FolderDownloadService` (or move to DownloadManager) | `downloadFolder()` batch logic (lines 283-311) |
| `FileIconBadge.swift` | File type icon with extension label |
| Replace `print()` with `os.Logger` | 6 print statements |

---

### 10. UserProfileSheet.swift (318 lines)

Profile display + privileges popover + 6 stats + action buttons.

| Extract To | What |
|-----------|------|
| `UserProfileHeader.swift` | Picture, name, status |
| `UserProfileStats.swift` | Stats grid (6 StatItems) |
| `UserProfileInterests.swift` | Likes + dislikes tags |
| `GivePrivilegesPopover.swift` | Privileges popover content |

---

### 11. RoomManagementSheet.swift (334 lines)

Member and operator management sections are near-identical.

| Extract To | What |
|-----------|------|
| `RoomMemberListSection.swift` | Parameterized: works for both members and operators |
| `RoomInfoSection.swift` | Room metadata display |
| `RoomTickerSection.swift` | Ticker management |

---

## P2 - Medium

### 12. Shared Cross-Feature Patterns to Extract

These patterns appear 3+ times across the codebase:

| Component | Used In | Current State |
|-----------|---------|---------------|
| `UserContextMenu` | TransferRow, HistoryRow, ChatView, RoomUserListPanel, BuddyRowView | Duplicated 5x |
| `OnlineStatusDot` | ChatView (2x), RoomUserListPanel, BuddyRowView | Duplicated 4x |
| `UnreadBadge` | ChatView (2x), RoomBrowserSheet | Duplicated 3x |
| `RoomRoleIcon` | ChatView, RoomBrowserSheet, RoomManagementSheet | Duplicated 3x |
| `TimeFormatter` utility | SearchActivityView, LivePeersView, NetworkTopologyView, TransferState | Duplicated 4x |
| `DateFormatter` (cached) | BlocklistView, HistoryRow, TransferHistoryItem | Created on every render |

---

### 13. State Defined in Wrong Files

| State Class | Currently In | Move To |
|-------------|-------------|---------|
| `SearchActivityState` | SearchActivityView.swift | `Features/Statistics/SearchActivityState.swift` |
| `ActivityLog` | LiveActivityFeed.swift | `Features/Statistics/ActivityLog.swift` |
| `LeechSettings` logic | SettingsView.swift (inline) | Already in SocialState - just extract the view |

---

### 14. ConnectionBadge.swift (166 lines)

3 unrelated badge components in one file.

| Extract To | What |
|-----------|------|
| `ConnectionBadge.swift` | Keep: ConnectionStatus enum + badge |
| `SpeedBadge.swift` | Speed display with direction |
| `ProgressIndicator.swift` | Progress bar with optional percentage |

---

### 15. Medium-Sized Views to Split

| File | Lines | Action |
|------|-------|--------|
| `LeechSettingsView.swift` | 301 | Split config from detected leeches list |
| `SimilarUsersView.swift` | 286 | Extract `SimilarUserRow`, `RecommendationTags` |
| `MyProfileView.swift` | 277 | Extract `ProfilePicturePicker`, move JPEG compression to utility |
| `SearchView.swift` | 271 | Move `performSearch()` to SearchState |
| `WishlistView.swift` | 249 | Extract `WishlistItemRow.swift` |
| `InterestsView.swift` | 219 | Extract `InterestListSection` (reuse for likes/hates) |
| `RoomBrowserSheet.swift` | 230 | Extract `CreateRoomForm`, `RoomBrowserRow` |
| `LivePeersView.swift` | 358 | Extract `PeerRow.swift`, `PeerInfoPopover.swift` |
| `LiveActivityFeed.swift` | 327 | Extract `ActivityLog` to own file |
| `NetworkTopologyView.swift` | 355 | Extract `PeerNode`, `ConnectionLine`, `PeerDetailPopover` |
| `SearchActivityView.swift` | 345 | Extract `SearchEventRow`, `IncomingSearchRow`, `SearchTimeline` |
| `MetadataEditorSheet.swift` | 403 | Extract `CoverArtEditView`, `RecordingSearchResults` |

---

### 16. SettingsState.swift - Repetitive didSet (363 lines)

Every setting property has identical boilerplate:
```swift
var foo: Type = default {
    didSet { guard !isLoading else { return }; save() }
}
```

**Fix:** Create a `@SettingProperty` property wrapper or extract save-on-change into a centralized observer pattern.

---

### 17. BrowseState.swift - Debug Prints (580 lines)

20+ `print()` statements scattered through browse logic. Replace with `os.Logger`.

---

## P3 - Low

### 18. FormStyles.swift (172 lines)

Could split `SeeleTextFieldStyle` and `SeeleToggleStyle` into separate files, but low impact.

---

### 19. Preview Support Checklist

Every extracted view must include `#Preview`. Pattern:

```swift
#Preview {
    ExtractedView(/* minimal mock props */)
        .frame(width: 400) // if needed
        .background(SeeleColors.background)
}
```

For views requiring `AppState`:
```swift
#Preview {
    ExtractedView()
        .environment(\.appState, AppState())
}
```

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| **Files audited** | ~45 |
| **Files exceeding 150 lines** | 30 |
| **Files with SRP violations** | 28 |
| **P0 Critical extractions** | 5 files -> ~30 new files |
| **P1 High extractions** | 6 files -> ~25 new files |
| **P2 Medium extractions** | ~15 files -> ~25 new files |
| **Shared components to create** | 6 cross-feature |
| **Estimated total new files** | ~80 |

---

## Execution Order

1. **P0 items 1-2** first (SettingsView, BrowseView) - highest line counts, most tangled logic
2. **P1 item 6** (StandardComponents) - unblocks cleaner component usage everywhere
3. **P0 items 3-5** (StatisticsView, NetworkMonitorView, ChatView)
4. **P1 items 7-11** (FileVisualization, TransfersView dedup, SearchResultRow, UserProfile, RoomManagement)
5. **P2 items 12-13** (shared patterns, state relocation)
6. **P2 items 14-17** (medium splits, property wrapper, debug prints)
7. **P3** (FormStyles, final cleanup)
