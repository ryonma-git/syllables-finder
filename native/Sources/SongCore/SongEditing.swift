import Foundation

extension SongDocument {
    public mutating func updateNote(id: UUID, pitch: Int, onset: Beat, duration: Beat, velocity: Int) throws {
        guard let index = music.events.firstIndex(where: { $0.id == id }), var note = music.events[index].note else {
            throw SongError.invalid("編集する音符が見つかりません。")
        }
        note.pitch = pitch; note.velocity = velocity
        music.events[index].content = .note(note)
        music.events[index].onset = onset; music.events[index].duration = duration
        music.events[index].measureID = music.measures.first { $0.range.start <= onset && onset < $0.range.end }?.id
        // Phrase bounds and sub-note alignments are checked at transaction commit.
    }

    public mutating func removeNote(id: UUID) {
        music.events.removeAll { $0.id == id }
        for i in phrases.indices { phrases[i].musicalEventIDs.removeAll { $0 == id } }
        for i in music.spans.indices { music.spans[i].eventIDs.removeAll { $0 == id } }
        for i in alignments.indices {
            alignments[i].musicTargets.removeAll { target in
                if case .event(let eventID, _) = target { return eventID == id }
                return false
            }
        }
        alignments.removeAll { $0.musicTargets.isEmpty }
    }

    public mutating func align(syllableID: UUID, to eventIDs: [UUID]) throws {
        guard syllable(syllableID) != nil else { throw SongError.invalid("音節が見つかりません。") }
        let target = LanguageTarget(.syllable, syllableID)
        // Keep the other language targets of a many-to-many alignment intact.
        for i in alignments.indices { alignments[i].languageTargets.removeAll { $0 == target } }
        alignments.removeAll { $0.languageTargets.isEmpty }
        if !eventIDs.isEmpty {
            alignments.append(.init(languageTargets: [target], musicTargets: eventIDs.map { .event($0) }, relation: .manual, userEdited: true))
        }
    }

    /// Manual text entry creates words only. No guessed syllables or IPA are manufactured.
    public mutating func appendPhrase(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var phrase = Phrase(originalText: text)
        phrase.structureUserEdited = true
        for token in text.split(whereSeparator: \.isWhitespace) {
            var word = Word(parentPhraseID: phrase.id, surface: String(token))
            word.structureUserEdited = true
            phrase.wordIDs.append(word.id); words.append(word)
        }
        if sections.isEmpty { sections.append(.init(title: "歌詞")) }
        sections[sections.count - 1].phraseIDs.append(phrase.id); phrases.append(phrase)
    }
}
