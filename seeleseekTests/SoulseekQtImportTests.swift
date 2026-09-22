import Testing
import Foundation
@testable import seeleseek

@Suite("SoulseekQt config import")
struct SoulseekQtImportTests {

    /// Builds an `.scd1` body: tables of (id, value) nodes, then links.
    /// Same framing as SoulseekQt's export.
    static func scd(tables: [(String, [(UInt32, String)])], links: [(UInt32, UInt32)]) -> Data {
        var data = Data()
        func u32(_ value: UInt32) {
            var le = value.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        func string(_ value: String) {
            let bytes = Array(value.utf8)
            u32(UInt32(bytes.count))
            data.append(contentsOf: bytes)
        }
        u32(UInt32(tables.count))
        for (name, nodes) in tables {
            string(name)
            u32(UInt32(nodes.count))
            for (id, value) in nodes {
                u32(id)
                string(value)
            }
        }
        u32(UInt32(links.count))
        for (a, b) in links {
            u32(a)
            u32(b)
        }
        return data
    }

    /// Mirrors the node layout of a real export: `global` keys link to
    /// shared `global_value` nodes, entities link to flag nodes in
    /// whichever direction SoulseekQt happened to write them.
    static let fixture = scd(
        tables: [
            ("global", [
                (1, "username"), (2, "password"), (3, "listening_port"),
                (4, "download_folder"), (5, "upload_slots"),
                (6, "upload_speed_limit"), (7, "upload_speed_limit_enabled"),
                (8, "download_speed_limit"), (9, "download_speed_limit_enabled"),
                (10, "new_listening_port"),
            ]),
            ("global_value", [
                (20, "testuser"), (21, "s3cr3t pass"), (22, "51958"),
                (23, "/Users/test/Soulseek Downloads"), (24, "3"),
                (25, "500"), (26, "yes"), (27, "0"), (28, "no"),
            ]),
            ("shared_folder", [(30, "/Users/test/Music"), (31, "/Users/test/Rips"), (32, "/Users/test/Music")]),
            ("shared_public", [(33, "1")]),
            ("user", [(40, "spammer1"), (41, "buddy"), (42, "leech9")]),
            ("is_ignored", [(43, "1"), (44, "0")]),
            ("in_user_list", [(45, "1")]),
            ("room", [(50, "indie music"), (51, "quiet room")]),
            ("room_autojoin", [(52, "1"), (53, "0")]),
        ],
        links: [
            (1, 20), (2, 21), (3, 22), (4, 23), (5, 24),
            (6, 25), (7, 26), (8, 27), (9, 28),
            (30, 33), (31, 33),
            (40, 43), (43, 42), (41, 44), (41, 45),
            (50, 52), (53, 51),
        ]
    )

    @Test("Parses every mapped key from a realistic export")
    func fullFixture() throws {
        let config = try SoulseekQtConfigImporter.parse(Self.fixture)

        #expect(config.username == "testuser")
        #expect(config.password == "s3cr3t pass")
        #expect(config.listenPort == 51958)
        #expect(config.downloadDirectory == "/Users/test/Soulseek Downloads")
        #expect(config.incompleteDirectory == nil)
        #expect(config.uploadSlots == 3)
        #expect(config.uploadSpeedLimit == 500)
        // A limit whose switch is off is unlimited.
        #expect(config.downloadSpeedLimit == 0)
        // Duplicate share collapsed.
        #expect(config.sharedFolders == ["/Users/test/Music", "/Users/test/Rips"])
        // Flags linked in either direction count; "0" flags do not.
        #expect(config.ignoredUsers == ["spammer1", "leech9"])
        #expect(config.autojoinRooms == ["indie music"])
    }

    @Test("A limit with the switch off is unlimited even when a number is stored")
    func disabledLimitIsUnlimited() throws {
        let data = Self.scd(
            tables: [
                ("global", [(1, "upload_speed_limit"), (2, "upload_speed_limit_enabled")]),
                ("global_value", [(3, "250"), (4, "no")]),
            ],
            links: [(1, 3), (2, 4)]
        )
        let config = try SoulseekQtConfigImporter.parse(data)
        #expect(config.uploadSpeedLimit == 0)
    }

    @Test("Out-of-range ports and empty values are rejected")
    func validation() throws {
        let data = Self.scd(
            tables: [
                ("global", [(1, "listening_port"), (2, "username"), (3, "upload_slots")]),
                ("global_value", [(4, "70000"), (5, ""), (6, "0")]),
            ],
            links: [(1, 4), (2, 5), (3, 6)]
        )
        let config = try SoulseekQtConfigImporter.parse(data)
        #expect(config.isEmpty)
    }

    @Test("A key without a linked value is absent")
    func unlinkedKey() throws {
        let data = Self.scd(
            tables: [("global", [(1, "username")]), ("global_value", [(2, "orphan")])],
            links: []
        )
        let config = try SoulseekQtConfigImporter.parse(data)
        #expect(config.username == nil)
    }

    @Test("Truncated and non-SCD data throw instead of yielding garbage")
    func malformed() {
        let truncated = Self.fixture.prefix(Self.fixture.count / 2)
        #expect(throws: SoulseekQtConfigImporter.MalformedFile.self) {
            try SoulseekQtConfigImporter.parse(truncated)
        }
        #expect(throws: SoulseekQtConfigImporter.MalformedFile.self) {
            try SoulseekQtConfigImporter.parse(Data("[server]\nlogin = nope\n".utf8))
        }
        #expect(throws: SoulseekQtConfigImporter.MalformedFile.self) {
            try SoulseekQtConfigImporter.parse(Data())
        }
    }

    @Test("An export with no tables is an empty config")
    func emptyExport() throws {
        let config = try SoulseekQtConfigImporter.parse(Self.scd(tables: [], links: []))
        #expect(config.isEmpty)
    }
}
