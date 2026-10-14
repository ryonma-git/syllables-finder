import Foundation

/// Practice melodies whose note groups were checked against the displayed source-language lyrics.
/// The older instrumental-only sequences are deliberately not used as a fallback.
enum SourceMelodies {
    static let scores = ReviewedSampleMelodies.scores

    static func attaching(_ key: String, to original: SongDocument) -> SongDocument {
        guard let score = scores[key], let index = scores.keys.sorted().firstIndex(of: key) else {
            preconditionFailure("Missing lyric-aligned score: \(key)")
        }
        return try! score.attaching(to: original, serial: index + 1)
    }
}
