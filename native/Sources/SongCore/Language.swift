import Foundation

public struct FieldSource: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case manual, sample, ai, dictionary, imported, rule }
    public var kind: Kind
    public var provider: String?
    public var model: String?
    public init(_ kind: Kind, provider: String? = nil, model: String? = nil) {
        self.kind = kind; self.provider = provider; self.model = model
    }
}

public struct GeneratedField<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var value: Value
    public var source: FieldSource
    public var userEdited: Bool
    public init(_ value: Value, source: FieldSource = .init(.sample), userEdited: Bool = false) {
        self.value = value; self.source = source; self.userEdited = userEdited
    }
    /// Records a user edit. Writing back the same value (for example when a text field only gains
    /// or loses focus) keeps the original source, so sample/AI values are not marked as manual.
    public mutating func edit(_ value: Value) {
        guard value != self.value else { return }
        self.value = value; source = .init(.manual); userEdited = true
    }
    public mutating func accept(_ value: Value, source: FieldSource) {
        guard !userEdited else { return }
        self.value = value; self.source = source
    }
}

public typealias TextFieldValue = GeneratedField<String>

public struct SongMetadata: Codable, Equatable, Sendable {
    public var title = "名称未設定"
    public var sourceLanguage = "en"
    public var translationLanguage = "ja"
    public var notes = ""
    public init(title: String = "名称未設定", sourceLanguage: String = "en") {
        self.title = title; self.sourceLanguage = sourceLanguage
    }
}

public struct Section: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var phraseIDs: [UUID]
    public init(id: UUID = UUID(), title: String, phraseIDs: [UUID] = []) {
        self.id = id; self.title = title; self.phraseIDs = phraseIDs
    }
}

public struct Phrase: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var originalText: String
    public var translation: TextFieldValue
    public var wordIDs: [UUID]
    public var timeRange: BeatRange?
    public var musicalEventIDs: [UUID]
    public var structureUserEdited = false
    /// BCP 47 language of this line; nil means the document's source language.
    public var language: String?
    public init(id: UUID = UUID(), originalText: String, translation: String = "", wordIDs: [UUID] = [],
                timeRange: BeatRange? = nil, musicalEventIDs: [UUID] = []) {
        self.id = id; self.originalText = originalText; self.translation = .init(translation)
        self.wordIDs = wordIDs; self.timeRange = timeRange; self.musicalEventIDs = musicalEventIDs
    }
}

public struct Word: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parentPhraseID: UUID
    public var surface: String
    public var lemma: TextFieldValue = .init("")
    public var partOfSpeech: TextFieldValue = .init("")
    public var contextualMeaning: TextFieldValue = .init("")
    public var dictionaryMeaning: TextFieldValue = .init("")
    public var notes: TextFieldValue = .init("")
    public var syllableIDs: [UUID]
    public var structureUserEdited = false
    public init(id: UUID = UUID(), parentPhraseID: UUID, surface: String, syllableIDs: [UUID] = []) {
        self.id = id; self.parentPhraseID = parentPhraseID; self.surface = surface; self.syllableIDs = syllableIDs
    }
}

public struct Syllable: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parentWordID: UUID
    public var text: TextFieldValue
    public var ipa: TextFieldValue
    public var reading: TextFieldValue
    public var stress: TextFieldValue = .init("")
    public var moraIDs: [UUID]
    /// Includes every phoneme, including those that also belong to a mora.
    public var phonemeIDs: [UUID]
    public var structureUserEdited = false
    public init(id: UUID = UUID(), parentWordID: UUID, text: String, ipa: String = "", reading: String = "",
                moraIDs: [UUID] = [], phonemeIDs: [UUID] = []) {
        self.id = id; self.parentWordID = parentWordID; self.text = .init(text)
        self.ipa = .init(ipa); self.reading = .init(reading); self.moraIDs = moraIDs; self.phonemeIDs = phonemeIDs
    }
}

public struct Mora: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parentSyllableID: UUID
    public var text: TextFieldValue
    public var ipa: TextFieldValue
    public var phonemeIDs: [UUID]
    public init(id: UUID = UUID(), parentSyllableID: UUID, text: String, ipa: String, phonemeIDs: [UUID] = []) {
        self.id = id; self.parentSyllableID = parentSyllableID
        self.text = .init(text); self.ipa = .init(ipa); self.phonemeIDs = phonemeIDs
    }
}

public struct Phoneme: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parentSyllableID: UUID
    public var parentMoraID: UUID?
    public var symbol: TextFieldValue
    public var ipa: TextFieldValue
    public var phoneticFeatures: [String: String]?
    public init(id: UUID = UUID(), parentSyllableID: UUID, parentMoraID: UUID? = nil, symbol: String) {
        self.id = id; self.parentSyllableID = parentSyllableID; self.parentMoraID = parentMoraID
        self.symbol = .init(symbol); self.ipa = .init(symbol)
    }
}
