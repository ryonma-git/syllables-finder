import Foundation
import Testing
@testable import SongCore

struct NinthPronunciationTests {
    @Test func stageSelectionSavesAndReturnsExactlyToStandard() throws {
        let original = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        var song = original
        NinthPronunciation.apply(.stage, to: &song)
        try song.validate()
        let brothers = try #require(song.words.first { $0.surface.hasPrefix("Brüder") })
        #expect(song.syllables(in: brothers).map(\.reading.value).joined() == "ブリューデル")
        #expect(song.syllables(in: brothers).map(\.ipa.value) == ["ˈbryː", "dər"])
        #expect(!song.syllables.contains { $0.ipa.value.contains("ɐ") || $0.ipa.value.contains("ʁ") })
        let saved = try SongDocument.decode(song.encoded())
        #expect(saved == song)
        #expect(saved.metadata.ninthPronunciation == .stage)
        song = saved
        NinthPronunciation.apply(.standard, to: &song)
        #expect(song == original)
    }

    @Test func manualPronunciationAndStructureSurviveBothDirections() throws {
        var song = try #require(SampleCatalog.entries.first { $0.id == "ninth" }).make()
        let index = try #require(song.syllables.firstIndex { $0.text.value == "der" })
        song.syllables[index].reading.edit("手修正")
        let edited = song.syllables[index]
        NinthPronunciation.apply(.stage, to: &song)
        #expect(song.syllables[index] == edited)
        NinthPronunciation.apply(.standard, to: &song)
        #expect(song.syllables[index] == edited)
        let original = song
        song.syllables[index].structureUserEdited = true
        NinthPronunciation.apply(.stage, to: &song)
        #expect(song.syllables[index].ipa == original.syllables[index].ipa)
        var mary = try #require(SampleCatalog.entries.first { $0.id == "mary" }).make()
        let unchanged = mary
        NinthPronunciation.apply(.stage, to: &mary)
        #expect(mary == unchanged)
    }

    @Test func olderMetadataStillDecodes() throws {
        let data = Data(#"{"title":"旧形式","sourceLanguage":"de","translationLanguage":"ja","notes":""}"#.utf8)
        let metadata = try JSONDecoder().decode(SongMetadata.self, from: data)
        #expect(metadata.ninthPronunciation == nil)
    }
}
