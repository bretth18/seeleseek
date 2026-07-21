import Testing
import Foundation
@testable import seeleseek

@Suite("Slash command parsing")
struct SlashCommandTests {

    @Test("Plain messages are not commands")
    func plainMessage() {
        #expect(SlashCommand.parse("hello world") == nil)
        #expect(SlashCommand.parse("half / measure") == nil)
        #expect(SlashCommand.parse("") == nil)
    }

    @Test("/me with text passes through for verbatim send")
    func meCommand() {
        #expect(SlashCommand.parse("/me waves hello") == .me)
        #expect(SlashCommand.parse("/ME shouts") == .me)
    }

    @Test("/me without text is unknown")
    func meWithoutText() {
        #expect(SlashCommand.parse("/me") == .unknown("/me"))
        #expect(SlashCommand.parse("/me   ") == .unknown("/me"))
    }

    @Test("/join takes a room argument")
    func joinCommand() {
        #expect(SlashCommand.parse("/join indie") == .join("indie"))
        #expect(SlashCommand.parse("/j indie") == .join("indie"))
        #expect(SlashCommand.parse("/join") == .unknown("/join"))
    }

    @Test("/leave and /clear take no argument")
    func leaveAndClear() {
        #expect(SlashCommand.parse("/leave") == .leave)
        #expect(SlashCommand.parse("/part") == .leave)
        #expect(SlashCommand.parse("/clear") == .clear)
    }

    @Test("Unknown commands are reported with their name")
    func unknownCommand() {
        #expect(SlashCommand.parse("/frobnicate now") == .unknown("/frobnicate"))
    }
}

@Suite("Username tab-completion")
struct UsernameCompletionTests {
    let users = ["alice", "Albert", "bob", "ALVIN"]

    @Test("Completes the last token case-insensitively, sorted")
    func basicCompletion() {
        let context = UsernameCompletion.complete(text: "hey al", candidates: users, previous: nil)
        #expect(context?.completedText == "hey Albert")
        #expect(context?.matches == ["Albert", "alice", "ALVIN"])
    }

    @Test("Repeated Tab cycles matches and wraps")
    func cycling() {
        var context = UsernameCompletion.complete(text: "al", candidates: users, previous: nil)
        #expect(context?.completedText == "Albert")

        context = UsernameCompletion.complete(text: "Albert", candidates: users, previous: context)
        #expect(context?.completedText == "alice")

        context = UsernameCompletion.complete(text: "alice", candidates: users, previous: context)
        #expect(context?.completedText == "ALVIN")

        context = UsernameCompletion.complete(text: "ALVIN", candidates: users, previous: context)
        #expect(context?.completedText == "Albert")
    }

    @Test("Editing after a completion starts a fresh match")
    func staleContextIgnored() {
        let first = UsernameCompletion.complete(text: "al", candidates: users, previous: nil)
        // User typed more; old context no longer matches the text.
        let fresh = UsernameCompletion.complete(text: "hello b", candidates: users, previous: first)
        #expect(fresh?.completedText == "hello bob")
    }

    @Test("No matches or empty stem yields nil")
    func noMatches() {
        #expect(UsernameCompletion.complete(text: "zzz", candidates: users, previous: nil) == nil)
        #expect(UsernameCompletion.complete(text: "hello ", candidates: users, previous: nil) == nil)
        #expect(UsernameCompletion.complete(text: "", candidates: users, previous: nil) == nil)
    }

    @Test("Completes mid-sentence tokens using preceding text as base")
    func midSentence() {
        let context = UsernameCompletion.complete(text: "thanks bo", candidates: users, previous: nil)
        #expect(context?.completedText == "thanks bob")
        #expect(context?.base == "thanks ")
    }
}
