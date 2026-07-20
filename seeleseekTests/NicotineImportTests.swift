import Testing
import Foundation
@testable import seeleseek

@Suite("Nicotine+ config import")
struct NicotineImportTests {

    static let fixture = """
    [server]
    server = ('server.slsknet.org', 2242)
    login = testuser
    passw = s3cr3t pass
    portrange = (2411, 2416)
    autojoin = ['nicotine', 'indie music']
    ignorelist = ['spammer1', 'spammer2']
    banlist = ['leech9', 'spammer1']

    [transfers]
    downloaddir = /Users/test/Music/slsk
    incompletedir = /Users/test/Music/slsk/incomplete
    uploadslots = 3
    uploadlimit = 500
    downloadlimit = 0
    shared = [('Music', '/Users/test/Music'), ('Rips', '/Users/test/Rips')]
    buddyshared = [('Private', '/Users/test/Private')]

    [ui]
    dark_mode = True
    """

    @Test("Parses every mapped key from a realistic config")
    func fullFixture() {
        let config = NicotineConfigImporter.parse(Self.fixture)

        #expect(config.username == "testuser")
        #expect(config.password == "s3cr3t pass")
        #expect(config.listenPort == 2411)
        #expect(config.autojoinRooms == ["nicotine", "indie music"])
        // banlist merged, deduplicated against ignorelist
        #expect(config.ignoredUsers == ["spammer1", "spammer2", "leech9"])
        #expect(config.downloadDirectory == "/Users/test/Music/slsk")
        #expect(config.incompleteDirectory == "/Users/test/Music/slsk/incomplete")
        #expect(config.uploadSlots == 3)
        #expect(config.uploadSpeedLimit == 500)
        #expect(config.downloadSpeedLimit == 0)
        #expect(config.sharedFolders == ["/Users/test/Music", "/Users/test/Rips", "/Users/test/Private"])
    }

    @Test("Old-style share lists of plain strings are accepted")
    func plainStringShares() {
        let config = NicotineConfigImporter.parse("""
        [transfers]
        shared = ['/Users/test/Music', '/Users/test/Rips']
        """)
        #expect(config.sharedFolders == ["/Users/test/Music", "/Users/test/Rips"])
    }

    @Test("Corrupt values are skipped, not fatal")
    func corruptValues() {
        let config = NicotineConfigImporter.parse("""
        [server]
        login = gooduser
        portrange = (99999999
        autojoin = [unterminated
        [transfers]
        uploadslots = not_a_number
        shared = 42
        """)
        #expect(config.username == "gooduser")
        #expect(config.listenPort == nil)
        #expect(config.autojoinRooms.isEmpty)
        #expect(config.uploadSlots == nil)
        #expect(config.sharedFolders.isEmpty)
    }

    @Test("Empty lists, empty strings, and missing sections yield an empty config")
    func emptyConfig() {
        let config = NicotineConfigImporter.parse("""
        [server]
        login =
        autojoin = []
        """)
        #expect(config.isEmpty)
    }

    @Test("Quoted strings handle escapes")
    func quotedEscapes() {
        let config = NicotineConfigImporter.parse(#"""
        [server]
        autojoin = ['it\'s a room', "with \"quotes\""]
        """#)
        #expect(config.autojoinRooms == ["it's a room", #"with "quotes""#])
    }

    @Test("Out-of-range ports are rejected")
    func portValidation() {
        let config = NicotineConfigImporter.parse("""
        [server]
        portrange = (0, 5)
        """)
        #expect(config.listenPort == nil)
    }
}
