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

public enum Clef: String, Codable, CaseIterable, Sendable {
    case treble, treble8vb, bass
    /// Diatonic index (octave × 7 + letter, C = 0) of the bottom staff line.
    public var bottomLineDiatonic: Int {
        switch self {
        case .treble: 4 * 7 + 2     // E4
        case .treble8vb: 3 * 7 + 2  // E3
        case .bass: 2 * 7 + 4       // G2
        }
    }
    public var label: String {
        switch self {
        case .treble: "ト音記号"
        case .treble8vb: "ト音記号（1オクターブ下）"
        case .bass: "ヘ音記号"
        }
    }
    /// A readable default for a sung range, by median pitch.
    public static func suggested(forPitches pitches: [Int]) -> Clef {
        guard !pitches.isEmpty else { return .treble }
        let median = pitches.sorted()[pitches.count / 2]
        return median >= 60 ? .treble : median >= 50 ? .treble8vb : .bass
    }
}

public struct MusicalEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var onset: Beat
    public var duration: Beat
    public var measureID: UUID?
    public var content: EventContent
    /// Required from schemaVersion 2: the voice part this note or rest belongs to.
    public var partID: UUID?
    public init(id: UUID = UUID(), onset: Beat, duration: Beat, measureID: UUID? = nil, content: EventContent, partID: UUID? = nil) {
        self.id = id; self.onset = onset; self.duration = duration; self.measureID = measureID; self.content = content
        self.partID = partID
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

/// A voice part (for example soprano, or the single melody of a solo song). Parts share the
/// document's measures, tempo and meter; they are synchronised by Beat, never by recording time.
public struct Part: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var abbreviation: String
    public var clef: Clef
    /// The phrases this part sings, in order (repeats allowed). nil means every phrase in document order.
    public var phraseIDs: [UUID]?
    public init(id: UUID = UUID(), name: String, abbreviation: String = "", clef: Clef = .treble, phraseIDs: [UUID]? = nil) {
        self.id = id; self.name = name; self.abbreviation = abbreviation; self.clef = clef; self.phraseIDs = phraseIDs
    }
}

public struct Music: Codable, Equatable, Sendable {
    public var measures: [Measure] = []
    public var events: [MusicalEvent] = []
    public var tempos: [Tempo] = [.init(bpm: 88)]
    public var meters: [Meter] = [.init()]
    public var spans: [MusicSpan] = []
    public var parts: [Part] = []
    public init() {}

    private enum CodingKeys: String, CodingKey { case measures, events, tempos, meters, spans, parts }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measures = try c.decode([Measure].self, forKey: .measures)
        events = try c.decode([MusicalEvent].self, forKey: .events)
        tempos = try c.decode([Tempo].self, forKey: .tempos)
        meters = try c.decode([Meter].self, forKey: .meters)
        spans = try c.decode([MusicSpan].self, forKey: .spans)
        // Absent in schemaVersion 1; the document migration creates them.
        parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
    }

    public func part(_ id: UUID?) -> Part? { parts.first { $0.id == id } }
    public func events(in partID: UUID) -> [MusicalEvent] { events.filter { $0.partID == partID } }
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
