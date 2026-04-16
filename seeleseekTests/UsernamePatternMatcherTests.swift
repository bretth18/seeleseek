import Testing
import Foundation
@testable import SeeleseekCore

/// Tests for the glob-style username matcher used to auto-block bot accounts.
@Suite("Username Pattern Matcher")
struct UsernamePatternMatcherTests {

    // MARK: - Prefix wildcard

    @Test("slsk_* matches slsk_-prefixed names")
    func prefixWildcardMatches() {
        #expect(UsernamePatternMatcher.matches("slsk_bot42", anyOf: ["slsk_*"]))
        #expect(UsernamePatternMatcher.matches("slsk_", anyOf: ["slsk_*"]))
        #expect(UsernamePatternMatcher.matches("SLSK_LoudUser", anyOf: ["slsk_*"]))
    }

    @Test("slsk_* does not match unrelated names")
    func prefixWildcardRejects() {
        #expect(!UsernamePatternMatcher.matches("vinyl_archivist", anyOf: ["slsk_*"]))
        #expect(!UsernamePatternMatcher.matches("myslsk_user", anyOf: ["slsk_*"]))
    }

    // MARK: - Suffix wildcard

    @Test("*_bot matches bot-suffixed names")
    func suffixWildcard() {
        #expect(UsernamePatternMatcher.matches("streaming_bot", anyOf: ["*_bot"]))
        #expect(UsernamePatternMatcher.matches("_bot", anyOf: ["*_bot"]))
        #expect(!UsernamePatternMatcher.matches("bot_streaming", anyOf: ["*_bot"]))
    }

    // MARK: - Middle wildcard

    @Test("stream*service matches with middle wildcard")
    func middleWildcard() {
        #expect(UsernamePatternMatcher.matches("stream_bot_service", anyOf: ["stream*service"]))
        #expect(UsernamePatternMatcher.matches("streamservice", anyOf: ["stream*service"]))
        #expect(!UsernamePatternMatcher.matches("streamed_content", anyOf: ["stream*service"]))
    }

    // MARK: - Multiple wildcards

    @Test("*bot* matches anywhere in name")
    func doubleWildcard() {
        #expect(UsernamePatternMatcher.matches("music_bot_42", anyOf: ["*bot*"]))
        #expect(UsernamePatternMatcher.matches("bot", anyOf: ["*bot*"]))
        #expect(UsernamePatternMatcher.matches("bots_r_us", anyOf: ["*bot*"]))
        #expect(!UsernamePatternMatcher.matches("audiophile", anyOf: ["*bot*"]))
    }

    // MARK: - Literal (no wildcard)

    @Test("Pattern without * requires exact match")
    func literalMatch() {
        #expect(UsernamePatternMatcher.matches("demo_user", anyOf: ["demo_user"]))
        #expect(UsernamePatternMatcher.matches("DEMO_USER", anyOf: ["demo_user"]))
        #expect(!UsernamePatternMatcher.matches("demo_user_2", anyOf: ["demo_user"]))
        #expect(!UsernamePatternMatcher.matches("my_demo_user", anyOf: ["demo_user"]))
    }

    // MARK: - Multiple patterns

    @Test("Username matches if any pattern in list matches")
    func multiplePatterns() {
        let patterns = ["slsk_*", "*_bot", "leech"]
        #expect(UsernamePatternMatcher.matches("slsk_abc", anyOf: patterns))
        #expect(UsernamePatternMatcher.matches("evil_bot", anyOf: patterns))
        #expect(UsernamePatternMatcher.matches("leech", anyOf: patterns))
        #expect(!UsernamePatternMatcher.matches("good_user", anyOf: patterns))
    }

    // MARK: - Edge cases

    @Test("Empty pattern list never matches")
    func emptyPatternList() {
        #expect(!UsernamePatternMatcher.matches("anyone", anyOf: []))
    }

    @Test("Whitespace-only patterns are ignored (do not match everyone)")
    func whitespacePatternsIgnored() {
        #expect(!UsernamePatternMatcher.matches("anyone", anyOf: ["   ", ""]))
        // But a real pattern alongside an empty one still works.
        #expect(UsernamePatternMatcher.matches("slsk_x", anyOf: ["   ", "slsk_*"]))
    }

    @Test("Lone * matches any non-empty username")
    func loneWildcard() {
        #expect(UsernamePatternMatcher.matches("anyone", anyOf: ["*"]))
        #expect(UsernamePatternMatcher.matches("", anyOf: ["*"]))
    }

    @Test("Pattern with surrounding whitespace is trimmed before matching")
    func patternTrimming() {
        #expect(UsernamePatternMatcher.matches("slsk_x", anyOf: ["  slsk_*  "]))
    }
}
