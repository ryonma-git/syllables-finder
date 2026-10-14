import Foundation
import Testing
@testable import SongCore

struct PronunciationRecoveryTests {
    static func legacy(_ surface: String, _ texts: [String]) -> SongDocument {
        var song = SongDocument()
        song.appendPhrase(text: surface, language: "en", syllabify: true)
        let id = song.words[0].id
        song.syllables = texts.map { Syllable(parentWordID: id, text: $0) }
        song.words[0].syllableIDs = song.syllables.map(\.id)
        return song
    }

    @Test func dictionaryBackedRuleRepairsAndRoundTrip() throws {
        for (surface, parts, count) in [("expression", ["ex", "pres", "si", "on"], 3),
                                        ("everything", ["e", "ve", "ry", "thing"], 3),
                                        ("Loneliness", ["Lo", "ne", "li", "ness"], 3)] {
            var song = Self.legacy(surface, parts)
            let before = song
            EnglishPronunciation.repairAutomaticSegmentation(in: &song)
            EnglishPronunciation.apply(to: &song)
            #expect(song.syllables.count == count)
            #expect(song.syllables.map(\.text.value).joined() == parts.joined())
            #expect(song.phrases == before.phrases)
            #expect(song.words[0].id == before.words[0].id)
            #expect(song.music == before.music && song.alignments == before.alignments)
            #expect(try SongDocument.decode(song.encoded()) == song)
        }
    }

    @Test func manualAndAlignedGroupsRetainIDsAndUseWholeWordFallback() throws {
        for protection in ["manual", "alignment", "phoneme", "stress", "reading"] {
            var song = Self.legacy("expression", ["ex", "pres", "si", "on"])
            switch protection {
            case "manual": song.words[0].structureUserEdited = true
            case "alignment":
                song.alignments = [.init(languageTargets: [.init(.syllable, song.syllables[0].id)],
                    musicTargets: [.timeRange(.init(start: .zero, end: try Beat(1)))], relation: .manual)]
            case "phoneme":
                let item = Phoneme(parentSyllableID: song.syllables[0].id, symbol: "ɪ")
                song.phonemes = [item]; song.syllables[0].phonemeIDs = [item.id]
            case "stress": song.syllables[0].stress.edit("弱")
            default: song.syllables[0].reading.edit("手修正")
            }
            let before = song
            EnglishPronunciation.repairAutomaticSegmentation(in: &song)
            EnglishPronunciation.apply(to: &song)
            #expect(song.syllables == before.syllables)
            #expect(song.alignments == before.alignments && song.phonemes == before.phonemes)
            if protection != "reading" {
                #expect(song.pronunciationDisplay(for: song.words[0]).notice != nil)
                #expect(!song.pronunciationDisplay(for: song.words[0]).ipa.isEmpty)
                #expect(PronunciationAudit.entries(in: song)[0].status == .review)
            } else { #expect(song.pronunciationDisplay(for: song.words[0]).whole == nil) }
            try song.validate()
        }
    }

    @Test func fallbackIsInvalidatedByAccentSurfaceOrManualPronunciation() throws {
        var song = Self.legacy("expression", ["ex", "pres", "si", "on"])
        song.words[0].structureUserEdited = true
        EnglishPronunciation.apply(to: &song)
        let saved = song
        song.metadata.englishPronunciation = .british
        #expect(song.pronunciationDisplay(for: song.words[0]).whole == nil)
        song = saved; song.words[0].surface = "changed"
        #expect(song.pronunciationDisplay(for: song.words[0]).whole == nil)
        song = saved; song.syllables[0].ipa.edit("manual")
        #expect(song.pronunciationDisplay(for: song.words[0]).whole == nil)
        // Legacy schema-2 files omit the new optional property.
        var object = try JSONSerialization.jsonObject(with: saved.encoded()) as! [String: Any]
        var words = object["words"] as! [[String: Any]]
        words[0].removeValue(forKey: "wholePronunciation"); object["words"] = words
        let old = try SongDocument.decode(JSONSerialization.data(withJSONObject: object))
        #expect(old.words[0].wholePronunciation == nil)
    }
}
