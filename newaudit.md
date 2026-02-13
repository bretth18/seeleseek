• Findings (highest severity first)

  - High: FolderContentsResponse parsing does not match protocol shape.
    MessageBuilder writes token -> folder -> numberOfFolders -> dir -> fileCount -> files in
    seeleseek/Core/Network/Protocol/MessageBuilder.swift:342, but parser reads token -> folder ->
    fileCount in seeleseek/Core/Network/Connections/PeerConnection.swift:1704.
    Protocol requires the number of folders + per-folder blocks (PROTOCOL_REFERENCE_FULL.md:2720,
    PROTOCOL_REFERENCE_FULL.md:2741). This will mis-parse multi-folder responses and can corrupt
    browse results.
  - High: TransferResponse builder omits file size on allowed == true download-response path.
    seeleseek/Core/Network/Protocol/MessageBuilder.swift:440 only writes token + bool (+reason
    when denied).
    Protocol 41a requires file size when allowed (PROTOCOL_REFERENCE_FULL.md:2812,
    PROTOCOL_REFERENCE_FULL.md:2821).
    Your parser expects that optional field (seeleseek/Core/Network/Connections/
    PeerConnection.swift:1621), so interop can fail against stricter clients.
  - High: Networking/protocol tests cannot run because test target does not compile.
    seeleseekTests/LiveServerTests.swift:81 calls missing API MessageBuilder.fileSearch(...)
    (current API is fileSearchMessage).
    Result: xcodebuild test exits before execution, so regressions in core protocol paths are
    currently unguarded.
  - High: Protocol parity is incomplete vs PROTOCOL_REFERENCE_FULL.md.
    ServerMessageCode lacks documented server codes including 11, 12, 25, 33, 34, 40, 50, 55, 58,
    59, 60, 62, 63, 73, 87, 88, 90, 124, 129, 138, 153 (seeleseek/Core/Network/Protocol/
    MessageCode.swift:6, reference list starts PROTOCOL_REFERENCE_FULL.md:231).
    PeerMessageCode lacks code 52 (seeleseek/Core/Network/Protocol/MessageCode.swift:160, spec
    PROTOCOL_REFERENCE_FULL.md:2948).
    DistributedMessageCode lacks 7 and 93 (seeleseek/Core/Network/Protocol/MessageCode.swift:207,
    spec PROTOCOL_REFERENCE_FULL.md:3145, PROTOCOL_REFERENCE_FULL.md:3162).
  - Medium: Several server parsers are still vulnerable to oversized-count payload amplification.
    parseRoomNamesAndCounts and handleJoinRoom use unbounded counts and allocate placeholder
    arrays directly from server values (seeleseek/Core/Network/Handlers/
    ServerMessageHandler.swift:225, seeleseek/Core/Network/Handlers/
    ServerMessageHandler.swift:260, seeleseek/Core/Network/Handlers/
    ServerMessageHandler.swift:247).
    Unlike MessageParser, these paths do not enforce max-item caps.
  - Medium: Command methods in NetworkClient still silently no-op in disconnect races.
    Pattern try await serverConnection?.send(...) appears in throwing API methods (seeleseek/Core/
    Network/NetworkClient.swift:1206, seeleseek/Core/Network/NetworkClient.swift:1307).
    If serverConnection is nil, these calls can succeed without sending, hiding operational
    failures.
  - Medium: Swift toolchain posture is not aligned to your “Swift 6.2 best practices” target.
    Project is still SWIFT_VERSION = 5.0 (seeleseek.xcodeproj/project.pbxproj:400,
    seeleseek.xcodeproj/project.pbxproj:451), even though newer isolation settings are partially
    enabled.
  - Medium: Networking core is functionally rich but not modular enough for maintainability/parity
    work.
    Very large files centralize many responsibilities: DownloadManager (2368 lines),
    PeerConnection (1920), NetworkClient (1674), ServerMessageHandler (1398). This increases
    protocol-change risk and makes behavior regressions harder to isolate.
  - Medium (UI architecture): Views are not consistently modularized around design-system
    primitives.
    Design components exist, but usage is sparse (for example, StandardCard, StandardToolbar,
    StandardTabBar are minimally used), while many screens hand-roll row/chrome patterns
    (seeleseek/Features/Search/Views/SearchResultRow.swift:20, seeleseek/Features/Search/Views/
    SearchView.swift:39).
    Large view files (DiagnosticsSection 408 lines, SearchResultRow 367, BrowseView 329) suggest
    feature-level decomposition is incomplete.

  Open questions / assumptions

  - I treated “full parity with Nicotine+” as including non-deprecated protocol coverage where
    practical; if you only want SoulseekQt-era parity, code-priority changes.
  - I assumed peer interoperability correctness is required, not just “works against this client
    pair.”

  Validation status

  - I ran xcodebuild test for networking/protocol-related tests, but build failed before tests ran
    due LiveServerTests API drift (MessageBuilder.fileSearch missing). No runtime test pass/fail
    signal is currently available.

  Skill note

  - SwiftUI skill used: Swift-Concurrency-Updates.md (no observation/environment-specific Apple
    doc file was present in the installed skill docs).
