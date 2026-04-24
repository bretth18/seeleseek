import Testing
import Foundation
@testable import SeeleseekCore
@testable import seeleseek

@Suite("Message Builder Tests")
struct MessageBuilderTests {

    @Test("Build login message has correct structure")
    func testLoginMessageStructure() {
        let message = MessageBuilder.loginMessage(username: "testuser", password: "testpass")

        // Should start with length (4 bytes)
        #expect(message.count > 8)

        // Read the length
        let length = message.readUInt32(at: 0)
        #expect(length != nil)
        #expect(Int(length!) + 4 == message.count) // length + 4 = total

        // Read the code (should be 1 for login)
        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.login.rawValue)
    }

    @Test("setListenPort without obfuscated port sends only the main port")
    func testSetListenPortPlainOnly() {
        let message = MessageBuilder.setListenPortMessage(port: 2234)
        // length + code(4) + port(4) = 12 bytes total
        #expect(message.count == 12)
        #expect(message.readUInt32(at: 4) == ServerMessageCode.setListenPort.rawValue)
        #expect(message.readUInt32(at: 8) == 2234)
    }

    @Test("setListenPort with obfuscated port appends obfuscation block")
    func testSetListenPortWithObfuscated() {
        let message = MessageBuilder.setListenPortMessage(port: 2234, obfuscatedPort: 2235)
        // length + code(4) + port(4) + obfuscation_type(4) + obfuscated_port(4) = 20 bytes total
        #expect(message.count == 20)
        #expect(message.readUInt32(at: 4) == ServerMessageCode.setListenPort.rawValue)
        #expect(message.readUInt32(at: 8) == 2234)
        #expect(message.readUInt32(at: 12) == ObfuscationType.rotated.rawValue)
        #expect(message.readUInt32(at: 16) == 2235)
    }

    @Test("setListenPort with obfuscatedPort=0 omits the obfuscation block")
    func testSetListenPortZeroObfuscatedOmitsBlock() {
        // 0 means no obfuscated listener bound — don't advertise a dead port.
        let message = MessageBuilder.setListenPortMessage(port: 2234, obfuscatedPort: 0)
        #expect(message.count == 12, "obfuscatedPort=0 must not append the obfuscation block")
    }

    @Test("Build ping message")
    func testPingMessage() {
        let message = MessageBuilder.pingMessage()

        // Ping is minimal: length(4) + code(4)
        #expect(message.count == 8)

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.ping.rawValue)
    }

    @Test("Build set online status message")
    func testSetOnlineStatusMessage() {
        let message = MessageBuilder.setOnlineStatusMessage(status: .online)

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.setOnlineStatus.rawValue)

        // Status value should be in payload
        let status = message.readUInt32(at: 8)
        #expect(status == UserStatus.online.rawValue)
    }

    @Test("Build file search message")
    func testFileSearchMessage() {
        let message = MessageBuilder.fileSearchMessage(token: 12345, query: "pink floyd")

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.fileSearch.rawValue)

        // Token should follow code
        let token = message.readUInt32(at: 8)
        #expect(token == 12345)

        // Query string should follow token
        let queryResult = message.readString(at: 12)
        #expect(queryResult?.string == "pink floyd")
    }

    @Test("Build join room message")
    func testJoinRoomMessage() {
        let message = MessageBuilder.joinRoomMessage(roomName: "TestRoom")

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.joinRoom.rawValue)

        let roomResult = message.readString(at: 8)
        #expect(roomResult?.string == "TestRoom")
    }

    @Test("Build leave room message")
    func testLeaveRoomMessage() {
        let message = MessageBuilder.leaveRoomMessage(roomName: "TestRoom")

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.leaveRoom.rawValue)
    }

    @Test("Build say in chat room message")
    func testSayInChatRoomMessage() {
        let message = MessageBuilder.sayInChatRoomMessage(roomName: "TestRoom", message: "Hello!")

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.sayInChatRoom.rawValue)

        let roomResult = message.readString(at: 8)
        #expect(roomResult?.string == "TestRoom")

        let msgResult = message.readString(at: 8 + (roomResult?.bytesConsumed ?? 0))
        #expect(msgResult?.string == "Hello!")
    }

    @Test("Build private message")
    func testPrivateMessage() {
        let message = MessageBuilder.privateMessageMessage(username: "recipient", message: "Hi there")

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.privateMessages.rawValue)
    }

    @Test("Build shared folders files message")
    func testSharedFoldersFilesMessage() {
        let message = MessageBuilder.sharedFoldersFilesMessage(folders: 10, files: 500)

        let code = message.readUInt32(at: 4)
        #expect(code == ServerMessageCode.sharedFoldersFiles.rawValue)

        let folders = message.readUInt32(at: 8)
        let files = message.readUInt32(at: 12)
        #expect(folders == 10)
        #expect(files == 500)
    }

    @Test("Messages with unicode strings")
    func testUnicodeStrings() {
        let message = MessageBuilder.fileSearchMessage(token: 1, query: "日本語 music")

        // Should not crash and should contain the query
        let queryResult = message.readString(at: 12)
        #expect(queryResult?.string == "日本語 music")
    }

    @Test("Messages with empty strings")
    func testEmptyStrings() {
        let message = MessageBuilder.fileSearchMessage(token: 1, query: "")

        // Should handle empty string gracefully
        let queryResult = message.readString(at: 12)
        #expect(queryResult?.string == "")
    }
}
