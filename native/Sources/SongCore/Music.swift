import Foundation

public struct Notation: Codable, Equatable, Sendable {
    public var spelling: String?
    public var voice: String?
    public var part: String?
    public var tieGroupID: UUID?
    public init(spelling: String? = nil, voice: String? = nil, part: String? = nil, tieGroupID: UUID? = nil) {
        self.spelling = spelling; self.voice = voice; self.part = part; self.tieGroupID = tieGroupID
    }
}

public struct Note: Codable, Equatable, Sendable {
    public var pitch: Int
    public var velocity: Int
    public var channel: Int?
    public var track: Int?
    public var notation: Notation?
    public init(pitch: Int, velocity: Int = 80, channel: Int? = 0, track: Int? = 0) {
        self.pitch = pitch; self.velocity = velocity; self.channel = channel; self.track = track
    }
    public var name: String {
        guard (0...127).contains(pitch) else { return "?" }
        return ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"][pitch % 12] + "\(pitch / 12 - 1)"
    }
}

public enum EventContent: Codable, Equatable, Sendable { case note(Note), rest }

public struct MusicalEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var onset: Beat
    public var duration: Beat
    public var measureID: UUID?
    public var content: EventContent
    public init(id: UUID = UUID(), onset: Beat, duration: Beat, measureID: UUID? = nil, content: EventContent) {
        self.id = id; self.onset = onset; self.duration = duration; self.measureID = measureID; self.content = content
    }
    public var note: Note? { if case .note(let note) = content { note } else { nil } }
    public var range: BeatRange { get throws { try BeatRange(start: onset, end: onset.adding(duration)) } }
}

public struct Measure: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var number: String
    public var range: BeatRange
    public init(id: UUID = UUID(), number: String, range: BeatRange) { self.id = id; self.number = number; self.range = range }
}

public struct Tempo: Codable, Equatable, Sendable {
    public var onset: Beat
    public var bpm: Double
    public init(onset: Beat = .zero, bpm: Double) { self.onset = onset; self.bpm = bpm }
}

public struct Meter: Codable, Equatable, Sendable {
    public var onset: Beat
    public var numerator: Int
    public var denominator: Int
    public init(onset: Beat = .zero, numerator: Int = 4, denominator: Int = 4) {
        self.onset = onset; self.numerator = numerator; self.denominator = denominator
    }
}

/// Musical form is independent of the linguistic Section/Phrase graph.
public struct MusicSpan: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case section, phrase }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var range: BeatRange
    public var eventIDs: [UUID]
    public init(id: UUID = UUID(), kind: Kind, title: String, range: BeatRange, eventIDs: [UUID]) {
        self.id = id; self.kind = kind; self.title = title; self.range = range; self.eventIDs = eventIDs
    }
}

public struct Music: Codable, Equatable, Sendable {
    public var measures: [Measure] = []
    public var events: [MusicalEvent] = []
    public var tempos: [Tempo] = [.init(bpm: 88)]
    public var meters: [Meter] = [.init()]
    public var spans: [MusicSpan] = []
    public init() {}
}

public struct LanguageTarget: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case word, syllable, mora, phoneme }
    public var kind: Kind
    public var id: UUID
    public init(_ kind: Kind, _ id: UUID) { self.kind = kind; self.id = id }
}

public enum MusicTarget: Codable, Hashable, Sendable {
    case event(UUID, relativeRange: BeatRange? = nil)
    case timeRange(BeatRange)
}

public struct Alignment: Codable, Equatable, Identifiable, Sendable {
    public enum Relation: String, Codable, Sendable { case oneToOne, syllabic, melisma, tie, elision, manual }
    public var id: UUID
    public var languageTargets: [LanguageTarget]
    public var musicTargets: [MusicTarget]
    public var relation: Relation
    public var userEdited: Bool
    public init(id: UUID = UUID(), languageTargets: [LanguageTarget], musicTargets: [MusicTarget],
                relation: Relation, userEdited: Bool = false) {
        self.id = id; self.languageTargets = languageTargets; self.musicTargets = musicTargets
        self.relation = relation; self.userEdited = userEdited
    }
}
