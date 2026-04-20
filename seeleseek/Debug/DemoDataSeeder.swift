#if DEBUG
import Foundation
import SeeleseekCore

/// Seeds realistic demo data into AppState for marketing screenshots.
/// Activated by launching the app with `--screenshots` argument
/// (typically from the UI test target).
/// Debug-only: release builds strip this entire file, avoiding hundreds of
/// KB of demo strings from shipping to users.
@MainActor
enum DemoDataSeeder {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--screenshots")
    }

    static func seed(into appState: AppState) {
        appState.connection.setConnected(
            username: "demo_user",
            ip: "192.0.2.42",
            greeting: "Welcome to SoulSeek! Enjoy sharing music."
        )

        seedSearch(appState.searchState)
        seedTransfers(appState.transferState)
        seedChat(appState.chatState)
        seedBrowse(appState.browseState)
        seedSocial(appState.socialState)
        seedWishlist(appState.wishlistState)
    }

    // MARK: - Search

    private static func seedSearch(_ state: SearchState) {
        state.searchHistory = [
            "computer data healing",
            "cindy lee diamond jubilee",
            "my bloody valentine loveless flac",
            "aphex twin selected ambient works"
        ]

        let query = SearchQuery(
            id: UUID(),
            query: "computer data healing flac",
            token: 0xDEAD_BEEF,
            timestamp: Date(timeIntervalSinceNow: -45),
            results: computerDataResults(),
            isSearching: false
        )
        state.searches = [query]
        state.selectedSearchIndex = 0
        state.searchQuery = query.query

        let second = SearchQuery(
            id: UUID(),
            query: "radiohead ok computer",
            token: 0xCAFE_BABE,
            timestamp: Date(timeIntervalSinceNow: -10),
            results: radioheadResults(),
            isSearching: true
        )
        state.searches.append(second)
    }

    private static func computerDataResults() -> [SearchResult] {
        let user1 = "lofihouse_terrorist"
        return [
            SearchResult(username: user1, filename: "@@music\\COMPUTER DATA\\2019 - Emotional Shift (FLAC)\\01 - Fog.flac",
                         size: 8_915_000, sampleRate: 96000, bitDepth: 24, freeSlots: true, uploadSpeed: 4_200_000, queueLength: 0),
            SearchResult(username: user1, filename: "@@music\\COMPUTER DATA\\2019 - Emotional Shift (FLAC)\\02 - Healing.flac",
                         size: 32_400_000, sampleRate: 96000, bitDepth: 24, freeSlots: true, uploadSpeed: 4_200_000, queueLength: 0),
            SearchResult(username: user1, filename: "@@music\\COMPUTER DATA\\2019 - Emotional Shift (FLAC)\\03 - U.flac",
                         size: 25_100_000, sampleRate: 96000, bitDepth: 24, freeSlots: true, uploadSpeed: 4_200_000, queueLength: 0)
        ]
    }

    private static func radioheadResults() -> [SearchResult] {
        return [
            SearchResult(username: "ok_computer_fan", filename: "@@radiohead\\OK Computer (1997) [FLAC]\\01 Airbag.flac",
                         size: 28_400_000, sampleRate: 44100, bitDepth: 16, freeSlots: true, uploadSpeed: 5_100_000, queueLength: 0),
            SearchResult(username: "ok_computer_fan", filename: "@@radiohead\\OK Computer (1997) [FLAC]\\02 Paranoid Android.flac",
                         size: 42_800_000, sampleRate: 44100, bitDepth: 16, freeSlots: true, uploadSpeed: 5_100_000, queueLength: 0),
            SearchResult(username: "shoegazer_91", filename: "Music\\Radiohead - OK Computer [320]\\01 - Airbag.mp3",
                         size: 11_200_000, bitrate: 320, freeSlots: true, uploadSpeed: 1_900_000, queueLength: 2)
        ]
    }

    // MARK: - Transfers

    private static func seedTransfers(_ state: TransferState) {
        state.totalDownloadSpeed = 4_350_000
        state.totalUploadSpeed = 1_120_000
        state.totalDownloaded = 1024 * 1024 * 1024 * 18      // 18 GiB
        state.totalUploaded = 1024 * 1024 * 1024 * 42        // 42 GiB

        state.downloads = [
            Transfer(username: "lofihouse_terrorist",
                     filename: "@@music\\COMPUTER DATA\\2019 - Emotional Shift (FLAC)\\02 - Healing.flac",
                     size: 32_400_000, direction: .download, status: .transferring,
                     bytesTransferred: 18_900_000, startTime: Date(timeIntervalSinceNow: -22), speed: 2_400_000),
            Transfer(username: "shoegazer_91",
                     filename: "shared\\My Bloody Valentine - Loveless (1991) [FLAC]\\04 - To Here Knows When.flac",
                     size: 38_700_000, direction: .download, status: .transferring,
                     bytesTransferred: 9_200_000, startTime: Date(timeIntervalSinceNow: -8), speed: 1_950_000),
            Transfer(username: "ok_computer_fan",
                     filename: "@@radiohead\\OK Computer (1997) [FLAC]\\02 Paranoid Android.flac",
                     size: 42_800_000, direction: .download, status: .queued,
                     queuePosition: 4),
            Transfer(username: "NeckBeard22",
                     filename: "Music\\Cindy Lee\\Diamond Jubilee [MP3 320]\\03 Baby Blue.mp3",
                     size: 6_500_000, direction: .download, status: .queued,
                     queuePosition: 14),
            Transfer(username: "audiophile_99",
                     filename: "@@flac\\Aphex Twin - Selected Ambient Works 85-92 [24-96]\\02 Xtal.flac",
                     size: 28_000_000, direction: .download, status: .completed,
                     bytesTransferred: 28_000_000, startTime: Date(timeIntervalSinceNow: -180), speed: 0)
        ]

        state.uploads = [
            Transfer(username: "driftwavecore",
                     filename: "Music\\Fennesz\\Endless Summer\\01 - Made In Hong Kong.flac",
                     size: 56_200_000, direction: .upload, status: .transferring,
                     bytesTransferred: 31_400_000, startTime: Date(timeIntervalSinceNow: -42), speed: 1_120_000),
            Transfer(username: "tapehiss",
                     filename: "Music\\Boards of Canada\\Music Has the Right to Children\\02 - An Eagle in Your Mind.flac",
                     size: 47_800_000, direction: .upload, status: .queued,
                     queuePosition: 1),
            Transfer(username: "rare_grooves",
                     filename: "Music\\Slowdive\\Souvlaki (Remastered)\\03 - Alison.flac",
                     size: 38_900_000, direction: .upload, status: .completed,
                     bytesTransferred: 38_900_000, startTime: Date(timeIntervalSinceNow: -240))
        ]
    }

    // MARK: - Chat

    private static func seedChat(_ state: ChatState) {
        let now = Date()
        let nyjazz = ChatRoom(
            name: "nicotine",
            users: ["djmixer", "lofihouse_terrorist", "audiophile_99", "NeckBeard22",
                    "tapehiss", "ok_computer_fan", "shoegazer_91", "driftwavecore",
                    "rare_grooves", "demo_user"],
            messages: [
                ChatMessage(timestamp: now.addingTimeInterval(-540), username: "djmixer",
                            content: "anyone got the new boards of canada lossless?", isOwn: false, isNewMessage: false),
                ChatMessage(timestamp: now.addingTimeInterval(-510), username: "tapehiss",
                            content: "yeah I'll share the folder", isOwn: false, isNewMessage: false),
                ChatMessage(timestamp: now.addingTimeInterval(-420), username: "shoegazer_91",
                            content: "Just uploaded the slowdive remasters btw", isOwn: false, isNewMessage: false),
                ChatMessage(timestamp: now.addingTimeInterval(-360), username: "demo_user",
                            content: "Thanks! grabbing now", isOwn: true, isNewMessage: false),
                ChatMessage(timestamp: now.addingTimeInterval(-180), username: "lofihouse_terrorist",
                            content: "cindy lee diamond jubilee is a top 10 album of the decade no cap", isOwn: false, isNewMessage: false),
                ChatMessage(timestamp: now.addingTimeInterval(-60), username: "ok_computer_fan",
                            content: "Anyone going to the radiohead reissue listening party?", isOwn: false)
            ],
            unreadCount: 0,
            isJoined: true,
            owner: "tapehiss",
            operators: ["tapehiss", "audiophile_99"],
            members: []
        )

        let flacRoom = ChatRoom(
            name: "lossless",
            users: ["audiophile_99", "driftwavecore", "demo_user"],
            messages: [
                ChatMessage(timestamp: now.addingTimeInterval(-1200), username: "audiophile_99",
                            content: "the loveless 2021 remaster finally fixes the low end imo", isOwn: false, isNewMessage: false)
            ],
            unreadCount: 2,
            isJoined: true
        )

        state.joinedRooms = [nyjazz, flacRoom]
        state.selectedRoom = "nicotine"

        state.availableRooms = [
            ChatRoom(name: "nicotine", users: Array(repeating: "x", count: 142)),
            ChatRoom(name: "lossless", users: Array(repeating: "x", count: 89)),
            ChatRoom(name: "jazz", users: Array(repeating: "x", count: 67)),
            ChatRoom(name: "vinyl-rips", users: Array(repeating: "x", count: 54)),
            ChatRoom(name: "ambient", users: Array(repeating: "x", count: 41)),
            ChatRoom(name: "metal", users: Array(repeating: "x", count: 38))
        ]

        state.privateChats = [
            PrivateChat(
                username: "lofihouse_terrorist",
                messages: [
                    ChatMessage(timestamp: now.addingTimeInterval(-3600), username: "lofihouse_terrorist",
                                content: "hey, saw you grabbed the computer data folder. enjoy!", isOwn: false, isNewMessage: false),
                    ChatMessage(timestamp: now.addingTimeInterval(-3540), username: "demo_user",
                                content: "thank you! the 24bit transfers sound incredible", isOwn: true, isNewMessage: false),
                    ChatMessage(timestamp: now.addingTimeInterval(-120), username: "lofihouse_terrorist",
                                content: "got the cindy lee diamond jubilee vinyl rip too if you want", isOwn: false)
                ],
                isOnline: true
            ),
            PrivateChat(
                username: "shoegazer_91",
                messages: [
                    ChatMessage(timestamp: now.addingTimeInterval(-86400), username: "shoegazer_91",
                                content: "any luck finding that mbv ep bootleg?", isOwn: false, isNewMessage: false)
                ],
                isOnline: false
            )
        ]
    }

    // MARK: - Browse

    private static func seedBrowse(_ state: BrowseState) {
        let folders: [SharedFile] = [
            SharedFile(filename: "Computer Data", isDirectory: true, children: [
                SharedFile(filename: "2019 - Emotional Shift (FLAC)", isDirectory: true, children: [
                    SharedFile(filename: "01 - Fog.flac", size: 8_915_000, bitrate: nil, duration: 90),
                    SharedFile(filename: "02 - Healing.flac", size: 32_400_000, duration: 163),
                    SharedFile(filename: "03 - U.flac", size: 25_100_000, duration: 216),
                    SharedFile(filename: "04 - Drift.flac", size: 38_700_000, duration: 421),
                    SharedFile(filename: "05 - Emotional Shift.flac", size: 27_300_000, duration: 285),
                    SharedFile(filename: "cover.jpg", size: 1_240_000)
                ], fileCount: 6),
                SharedFile(filename: "2021 - Bloom (FLAC)", isDirectory: true, fileCount: 5),
                SharedFile(filename: "2023 - Slow Wave (FLAC)", isDirectory: true, fileCount: 26)
            ], fileCount: 37),
            SharedFile(filename: "Cindy Lee", isDirectory: true, fileCount: 84),
            SharedFile(filename: "My Bloody Valentine", isDirectory: true, fileCount: 142),
            SharedFile(filename: "Aphex Twin", isDirectory: true, fileCount: 96),
            SharedFile(filename: "Boards of Canada", isDirectory: true, fileCount: 58)
        ]

        let shares = UserShares(username: "lofihouse_terrorist", folders: folders, isLoading: false)
        state.browses = [shares]
        state.selectedBrowseIndex = 0
        state.currentUser = "lofihouse_terrorist"
        state.browseHistory = ["lofihouse_terrorist", "audiophile_99", "ok_computer_fan"]
    }

    // MARK: - Social

    private static func seedSocial(_ state: SocialState) {
        state.buddies = [
            Buddy(username: "lofihouse_terrorist", status: .online, isPrivileged: true,
                  averageSpeed: 8_500_000, fileCount: 24_580, folderCount: 412,
                  countryCode: "US", notes: "Killer FLAC collection",
                  dateAdded: Date(timeIntervalSinceNow: -86400 * 90)),
            Buddy(username: "audiophile_99", status: .online,
                  averageSpeed: 2_900_000, fileCount: 8_120, folderCount: 96,
                  countryCode: "DE", dateAdded: Date(timeIntervalSinceNow: -86400 * 30)),
            Buddy(username: "shoegazer_91", status: .away,
                  averageSpeed: 1_500_000, fileCount: 12_400, folderCount: 230,
                  countryCode: "FR", notes: "MBV completist",
                  dateAdded: Date(timeIntervalSinceNow: -86400 * 180)),
            Buddy(username: "ok_computer_fan", status: .offline,
                  averageSpeed: 5_100_000, fileCount: 4_200, folderCount: 48,
                  countryCode: "UK",
                  dateAdded: Date(timeIntervalSinceNow: -86400 * 14),
                  lastSeen: Date(timeIntervalSinceNow: -3600 * 6))
        ]

        state.myLikes = ["computer data", "cindy lee", "my bloody valentine", "boards of canada", "aphex twin"]
        state.myHates = ["loudness war", "low bitrate"]
        state.myDescription = "Music enthusiast. Sharing FLAC rips since 2003. Be kind, share back."
        state.privilegeTimeRemaining = 86400 * 23
    }

    // MARK: - Wishlist

    private static func seedWishlist(_ state: WishlistState) {
        state.items = [
            WishlistItem(query: "boards of canada tomorrow's harvest 24bit",
                         createdAt: Date(timeIntervalSinceNow: -86400 * 7),
                         lastSearchedAt: Date(timeIntervalSinceNow: -1800),
                         resultCount: 3),
            WishlistItem(query: "aphex twin syro vinyl rip",
                         createdAt: Date(timeIntervalSinceNow: -86400 * 14),
                         lastSearchedAt: Date(timeIntervalSinceNow: -3600),
                         resultCount: 12),
            WishlistItem(query: "fennesz endless summer flac",
                         createdAt: Date(timeIntervalSinceNow: -86400 * 3),
                         lastSearchedAt: Date(timeIntervalSinceNow: -600),
                         resultCount: 0),
            WishlistItem(query: "burial untrue lossless",
                         createdAt: Date(timeIntervalSinceNow: -86400 * 30),
                         enabled: false,
                         lastSearchedAt: Date(timeIntervalSinceNow: -86400),
                         resultCount: 8)
        ]
    }
}
#endif
