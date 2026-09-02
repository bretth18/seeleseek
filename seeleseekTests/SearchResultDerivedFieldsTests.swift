import Testing
@testable import SeeleseekCore

@Suite("SearchResult derived fields")
struct SearchResultDerivedFieldsTests {

    private func result(_ path: String) -> SearchResult {
        SearchResult(username: "u", filename: path, size: 1)
    }

    @Test("Nested path splits into folder, display name, lowercased extension")
    func nestedPath() {
        let r = result("@@music\\Artist\\Album (FLAC)\\01 - Song.FLAC")
        #expect(r.displayFilename == "01 - Song.FLAC")
        #expect(r.folderPath == "@@music\\Artist\\Album (FLAC)")
        #expect(r.fileExtension == "flac")
        #expect(r.isLossless)
    }

    @Test("Bare filename has no folder")
    func bareFilename() {
        let r = result("song.mp3")
        #expect(r.displayFilename == "song.mp3")
        #expect(r.folderPath == "")
        #expect(r.fileExtension == "mp3")
    }

    @Test("No extension yields empty string, dots in folders are ignored")
    func noExtension() {
        let r = result("v1.2\\README")
        #expect(r.displayFilename == "README")
        #expect(r.folderPath == "v1.2")
        #expect(r.fileExtension == "")
    }

    @Test("formattedBytes keeps the file-style output")
    func formattedBytes() {
        #expect(Int64(0).formattedBytes == "0 KB")
        #expect(Int64(45_300_000).formattedBytes == "45.3 MB")
        #expect(Int64(1_234_567_890).formattedBytes == "1.23 GB")
    }
}
