import Foundation

/// Input to the local song-file generator. Lyric acquisition is deliberately outside this API.
public struct SongGenerationRequest: Codable, Sendable {
    public var title: String
    public var sourceLanguage: String
    public var lyrics: String
    public var sourceNote: String?
    public var sectionTitles: [String]?

    public init(title: String, sourceLanguage: String, lyrics: String,
                sourceNote: String? = nil, sectionTitles: [String]? = nil) {
        self.title = title
        self.sourceLanguage = sourceLanguage
        self.lyrics = lyrics
        self.sourceNote = sourceNote
        self.sectionTitles = sectionTitles
    }

    public func makeDocument() throws -> SongDocument {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { throw SongError.invalid("曲名は1〜200文字にしてください。") }
        guard Syllabifier.supports(sourceLanguage) else { throw SongError.invalid("対応していない言語です。") }
        guard lyrics.utf8.count <= 100_000 else { throw SongError.invalid("歌詞は100KB以内にしてください。") }
        guard (sourceNote?.count ?? 0) <= 2_000 else { throw SongError.invalid("出典メモは2000文字以内にしてください。") }

        let normalized = lyrics.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var groups: [[String]] = []
        var current: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count <= 1_000 else { throw SongError.invalid("歌詞の1行は1000文字以内にしてください。") }
            if line.isEmpty {
                if !current.isEmpty { groups.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { groups.append(current) }
        let lineCount = groups.reduce(0) { $0 + $1.count }
        guard lineCount > 0, lineCount <= 500 else { throw SongError.invalid("歌詞は1〜500行にしてください。") }
        if let sectionTitles {
            guard sectionTitles.count == groups.count,
                  sectionTitles.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 100 }) else {
                throw SongError.invalid("節の見出し数は、歌詞の段落数と同じにしてください。")
            }
        }

        var song = SongDocument()
        song.metadata = SongMetadata(title: title, sourceLanguage: sourceLanguage)
        song.metadata.notes = [sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                               "歌詞は入力データから作成。音節は規則による候補です。音符は未入力。"]
            .filter { !$0.isEmpty }.joined(separator: " ")
        song.music.parts = [.init(name: "歌詞のみ")]
        for (index, group) in groups.enumerated() {
            song.sections.append(.init(title: sectionTitles?[index].trimmingCharacters(in: .whitespacesAndNewlines)
                                            ?? "第\(index + 1)節"))
            for line in group { song.appendPhrase(text: line, language: sourceLanguage, syllabify: true) }
        }
        try song.validate()
        return song
    }
}
