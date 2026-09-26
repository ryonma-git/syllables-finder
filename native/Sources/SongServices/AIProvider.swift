import Foundation
import SongCore

public struct AIProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let structuredOutput = Self(rawValue: 1 << 0)
    public static let streaming = Self(rawValue: 1 << 1)
    public static let toolCalling = Self(rawValue: 1 << 2)
    public static let offline = Self(rawValue: 1 << 3)
    public static let ipaGeneration = Self(rawValue: 1 << 4)
    public static let translation = Self(rawValue: 1 << 5)
    public static let phoneticAnalysis = Self(rawValue: 1 << 6)
}

public struct LinguisticAnalysisRequest: Codable, Sendable {
    public struct Token: Codable, Sendable {
        public var id: UUID
        public var surface: String
    }
    public var documentID: UUID
    public var revision: UInt64
    public var phraseID: UUID
    public var sourceLanguage: String
    public var originalText: String
    public var words: [Token]
    public init(document: SongDocument, phrase: Phrase) {
        documentID = document.id; revision = document.revision; phraseID = phrase.id
        sourceLanguage = document.metadata.sourceLanguage; originalText = phrase.originalText
        words = document.words(in: phrase).map { .init(id: $0.id, surface: $0.surface) }
    }
}

public struct WordAnalysis: Codable, Sendable {
    public var id: UUID
    public var lemma: String
    public var partOfSpeech: String
    public var contextualMeaning: String
    public var dictionaryMeaning: String
    public init(id: UUID, lemma: String, partOfSpeech: String, contextualMeaning: String, dictionaryMeaning: String) {
        self.id = id; self.lemma = lemma; self.partOfSpeech = partOfSpeech
        self.contextualMeaning = contextualMeaning; self.dictionaryMeaning = dictionaryMeaning
    }
}

public struct LinguisticAnalysis: Codable, Sendable {
    public var translation: String
    public var words: [WordAnalysis]
    public init(translation: String, words: [WordAnalysis]) { self.translation = translation; self.words = words }
}

public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: AIProviderCapabilities { get }
    var source: FieldSource { get }
    func analyze(request: LinguisticAnalysisRequest) async throws -> LinguisticAnalysis
}

public enum ProviderError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case malformedResponse
    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .malformedResponse: "解析結果の形式を確認できませんでした。編集内容は保持されています。"
        }
    }
}

/// Only the original sample is supported; unknown words are never given invented meanings.
public struct MockAIProvider: AIProvider {
    public let id = "mock"
    public let displayName = "サンプル解析（通信なし）"
    public let capabilities: AIProviderCapabilities = [.offline, .structuredOutput, .translation]
    public var source: FieldSource { .init(.sample, provider: id) }
    public var fails: Bool
    public init(fails: Bool = false) { self.fails = fails }
    public func analyze(request: LinguisticAnalysisRequest) async throws -> LinguisticAnalysis {
        try Task.checkCancellation()
        if fails { throw ProviderError.unavailable("サンプルの接続失敗です。") }
        let sample = SampleSongDocument.make()
        guard let phrase = sample.phrases.first(where: { $0.originalText == request.originalText }),
              request.words.map(\.surface) == sample.words(in: phrase).map(\.surface) else {
            throw ProviderError.unavailable("サンプル解析は練習サンプルの英文に対応しています。")
        }
        let words = zip(request.words, sample.words(in: phrase)).map { token, word in
            WordAnalysis(id: token.id, lemma: word.lemma.value, partOfSpeech: word.partOfSpeech.value,
                         contextualMeaning: word.contextualMeaning.value, dictionaryMeaning: word.dictionaryMeaning.value)
        }
        return .init(translation: phrase.translation.value, words: words)
    }
}

public struct LinguisticAnalysisService: Sendable {
    public init() {}
    public func apply(_ analysis: LinguisticAnalysis, request: LinguisticAnalysisRequest,
                      source: FieldSource, to document: SongDocument) throws -> SongDocument {
        guard document.id == request.documentID, document.revision == request.revision,
              let phrase = document.phrase(request.phraseID), phrase.originalText == request.originalText,
              document.words(in: phrase).map(\.surface) == request.words.map(\.surface),
              phrase.wordIDs == request.words.map(\.id) else { throw SongError.staleAnalysis }
        let ids = analysis.words.map(\.id)
        guard Set(ids).count == ids.count, Set(ids) == Set(request.words.map(\.id)),
              analysis.translation.count <= 20_000,
              analysis.words.allSatisfy({ [$0.lemma, $0.partOfSpeech, $0.contextualMeaning, $0.dictionaryMeaning].allSatisfy { $0.count <= 4_000 } }) else {
            throw ProviderError.malformedResponse
        }
        return try document.editing { song in
            guard let p = song.phrases.firstIndex(where: { $0.id == request.phraseID }) else { throw SongError.staleAnalysis }
            song.phrases[p].translation.accept(analysis.translation, source: source)
            for value in analysis.words {
                guard let i = song.words.firstIndex(where: { $0.id == value.id }) else { throw ProviderError.malformedResponse }
                song.words[i].lemma.accept(value.lemma, source: source)
                song.words[i].partOfSpeech.accept(value.partOfSpeech, source: source)
                song.words[i].contextualMeaning.accept(value.contextualMeaning, source: source)
                song.words[i].dictionaryMeaning.accept(value.dictionaryMeaning, source: source)
            }
        }
    }
}
