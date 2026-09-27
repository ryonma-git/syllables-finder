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

    /// Replaces the syllable's alignment within one part (the part of `eventIDs`, or `partID`).
    /// Alignments of the same syllable in other parts are kept: each part sings its own timing.
    public mutating func align(syllableID: UUID, to eventIDs: [UUID], inPart partID: UUID? = nil) throws {
        guard syllable(syllableID) != nil else { throw SongError.invalid("音節が見つかりません。") }
        let target = LanguageTarget(.syllable, syllableID)
        let scope = partID ?? eventIDs.first.flatMap { event($0)?.partID }
        func inScope(_ alignment: Alignment) -> Bool {
            guard let scope else { return true }
            return alignment.musicTargets.contains { destination in
                if case .event(let id, _) = destination { return event(id)?.partID == scope }
                return false
            }
        }
        // Keep the other language targets of a many-to-many alignment intact.
        for i in alignments.indices where inScope(alignments[i]) { alignments[i].languageTargets.removeAll { $0 == target } }
        alignments.removeAll { $0.languageTargets.isEmpty }
        if !eventIDs.isEmpty {
            alignments.append(.init(languageTargets: [target], musicTargets: eventIDs.map { .event($0) }, relation: .manual, userEdited: true))
        }
    }

    /// Adds one lyric line. With `syllabify`, words and syllables come from the language rules and are
    /// marked as rule candidates (`FieldSource.rule`); without it, words only (the earlier behaviour).
    @discardableResult
    public mutating func appendPhrase(text: String, language: String, syllabify: Bool) -> UUID? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard syllabify, Syllabifier.supports(language) else {
            appendPhrase(text: text)
            if let last = phrases.indices.last, language != metadata.sourceLanguage { phrases[last].language = language }
            return phrases.last?.id
        }
        var phrase = Phrase(originalText: text)
        phrase.structureUserEdited = true
        if language != metadata.sourceLanguage { phrase.language = language }
        for token in Syllabifier.tokenize(text, language: language) {
            var word = Word(parentPhraseID: phrase.id, surface: token.surface)
            fill(&word, with: Syllabifier.syllabify(token, language: language))
            phrase.wordIDs.append(word.id); words.append(word)
        }
        if sections.isEmpty { sections.append(.init(title: "歌詞")) }
        sections[sections.count - 1].phraseIDs.append(phrase.id); phrases.append(phrase)
        return phrase.id
    }

    private mutating func fill(_ word: inout Word, with result: SyllabifiedWord) {
        let rule = FieldSource(.rule, provider: "Syllabifier")
        for (index, text) in result.syllables.enumerated() {
            var syllable = Syllable(parentWordID: word.id, text: text)
            syllable.text.source = rule
            if let reading = result.readings?[index] { syllable.reading = .init(reading, source: rule) }
            if index == result.stressIndex { syllable.stress = .init("強", source: rule) }
            word.syllableIDs.append(syllable.id); syllables.append(syllable)
        }
        if let note = result.note, !word.notes.userEdited { word.notes = .init(note, source: rule) }
    }

    public func language(of phrase: Phrase) -> String { phrase.language ?? metadata.sourceLanguage }

    /// Replaces a word's syllables with the given texts (a person's correction). With the same number
    /// of syllables the IDs, alignments and readings are kept; otherwise the old syllables and their
    /// alignments are removed rather than reassigned to different sounds.
    public mutating func setSyllables(wordID: UUID, texts: [String]) throws {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { throw SongError.invalid("単語が見つかりません。") }
        let texts = texts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let old = words[index].syllableIDs
        if texts.count == old.count {
            for (id, text) in zip(old, texts) {
                if let s = syllables.firstIndex(where: { $0.id == id }) { syllables[s].text.edit(text) }
            }
        } else {
            removeSyllables(old)
            words[index].syllableIDs = []
            for text in texts {
                var syllable = Syllable(parentWordID: wordID, text: text)
                syllable.text = .init(text, source: .init(.manual), userEdited: true)
                words[index].syllableIDs.append(syllable.id); syllables.append(syllable)
            }
        }
        words[index].structureUserEdited = true
    }

    /// Re-runs the language rules for one word. Words a person split by hand are left alone.
    public mutating func resyllabify(wordID: UUID, language: String) throws {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { throw SongError.invalid("単語が見つかりません。") }
        guard !words[index].structureUserEdited || words[index].syllableIDs.isEmpty else {
            throw SongError.invalid("手で区切った音節は規則で上書きしません。区切りを直接編集してください。")
        }
        removeSyllables(words[index].syllableIDs)
        words[index].syllableIDs = []
        var word = words[index]
        fill(&word, with: Syllabifier.syllabify(word.surface, language: language))
        words[index] = word
    }

    /// Splits the words of a phrase that have no syllables yet (for lyrics entered before rules existed).
    @discardableResult
    public mutating func syllabifyUnsplitWords(phraseID: UUID) -> Int {
        guard let phrase = phrase(phraseID) else { return 0 }
        let language = language(of: phrase)
        var count = 0
        for id in phrase.wordIDs {
            guard let index = words.firstIndex(where: { $0.id == id }), words[index].syllableIDs.isEmpty else { continue }
            var word = words[index]
            fill(&word, with: Syllabifier.syllabify(word.surface, language: language))
            words[index] = word
            count += word.syllableIDs.isEmpty ? 0 : 1
        }
        return count
    }

    private mutating func removeSyllables(_ ids: [UUID]) {
        let removed = Set(ids)
        let moraIDs = Set(moras.filter { removed.contains($0.parentSyllableID) }.map(\.id))
        moras.removeAll { removed.contains($0.parentSyllableID) }
        phonemes.removeAll { removed.contains($0.parentSyllableID) }
        syllables.removeAll { removed.contains($0.id) }
        for i in alignments.indices {
            alignments[i].languageTargets.removeAll { target in
                (target.kind == .syllable && removed.contains(target.id)) || (target.kind == .mora && moraIDs.contains(target.id))
            }
        }
        alignments.removeAll { $0.languageTargets.isEmpty }
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
