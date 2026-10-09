import Foundation
import SongCore
import Testing

struct PartsSchemaTests {
    /// Rewrites a current document into the version 1 layout (no parts, no partID).
    private func versionOneJSON(_ song: SongDocument) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: song.encoded()) as? [String: Any])
        object["schemaVersion"] = 1
        var music = try #require(object["music"] as? [String: Any])
        music.removeValue(forKey: "parts")
        music["events"] = (music["events"] as? [[String: Any]])?.map { event in
            var event = event; event.removeValue(forKey: "partID"); return event
        }
        object["music"] = music
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func samplesHaveOneMelodyPartThatOwnsEveryEvent() throws {
        for entry in SampleCatalog.entries {
            let song = entry.make()
            #expect(song.schemaVersion == 2)
            #expect(song.music.parts.count == 1)
            #expect(song.music.events.allSatisfy { $0.partID == song.music.parts[0].id })
            #expect(try SongDocument.decode(song.encoded()) == song)
        }
    }

    @Test func versionOneMigratesDeterministicallyAndKeepsTheOriginalBytes() throws {
        let original = TwinkleSample.make()
        let data = try versionOneJSON(original)
        let (migrated, from) = try SongDocument.decodeReportingMigration(data)
        #expect(from == 1)
        #expect(migrated.schemaVersion == 2)
        #expect(migrated.music.parts.map(\.name) == ["旋律"])
        #expect(migrated.music.parts[0].clef == .treble)
        #expect(migrated.music.events.allSatisfy { $0.partID == migrated.music.parts[0].id })
        #expect(try SongDocument.decode(data).music.parts[0].id == migrated.music.parts[0].id)
        #expect(migrated.alignments == original.alignments)

        let wrapper = FileWrapper(directoryWithFileWrappers: ["document.json": FileWrapper(regularFileWithContents: data)])
        let package = try DocumentPackage(reading: wrapper)
        #expect(package.attachmentPaths == ["preserved/document-v1.json"])
        let saved = try package.fileWrapper()
        let reopened = try DocumentPackage(reading: saved)
        #expect(reopened.song == migrated)
        let backup = saved.fileWrappers?["preserved"]?.fileWrappers?["document-v1.json"]?.regularFileContents
        #expect(backup == data)
    }

    @Test func versionOnePartLabelsBecomeParts() throws {
        var song = TwinkleSample.make()
        for index in song.music.events.indices {
            var note = song.music.events[index].note!
            note.notation = .init(part: index % 2 == 0 ? "Soprano" : "Alto")
            song.music.events[index].content = .note(note)
        }
        let migrated = try SongDocument.decode(versionOneJSON(song))
        #expect(migrated.music.parts.map(\.name) == ["Soprano", "Alto"])
        let alto = migrated.music.parts[1].id
        #expect(migrated.music.events[1].partID == alto)
        #expect(migrated.music.events(in: alto).count == 21)
    }

    @Test func partReferencesAreValidated() throws {
        var song = TwinkleSample.make()
        song.music.events[0].partID = UUID()
        #expect(throws: SongError.self) { try song.validate() }
        song.music.events[0].partID = nil
        #expect(throws: SongError.self) { try song.validate() }
        song.ensureParts()
        try song.validate()
        song.music.parts[0].phraseIDs = [UUID()]
        #expect(throws: SongError.self) { try song.validate() }
        song.music.parts[0].phraseIDs = [song.phrases[1].id, song.phrases[1].id] // repeats are allowed
        try song.validate()
        song.music.parts.removeAll()
        #expect(throws: SongError.self) { try song.validate() }
    }

    @Test func futureVersionsAreStillRejected() {
        #expect(throws: SongError.unsupportedVersion(3)) { try SongDocument.decode(Data("{\"schemaVersion\":3}".utf8)) }
    }
}
