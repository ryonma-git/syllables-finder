import Foundation
import SongCore
import SongServices

@main
struct SongGenerateTool {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Song generation failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard (args.count == 2 || args.count == 4 && args[2] == "--ollama"),
              args[1].hasSuffix(".songproj") else {
            throw SongError.invalid("Usage: SongGenerateTool input.json output.songproj [--ollama MODEL] (input.json may be - for stdin)")
        }
        let input: Data
        if args[0] == "-" { input = FileHandle.standardInput.readDataToEndOfFile() }
        else { input = try Data(contentsOf: URL(fileURLWithPath: args[0])) }
        guard input.count <= 200_000 else { throw SongError.invalid("入力JSONは200KB以内にしてください。") }
        let spec = try JSONDecoder().decode(SongGenerationRequest.self, from: input)
        var song = try spec.makeDocument()
        let output = URL(fileURLWithPath: args[1], isDirectory: true)
        let parent = output.deletingLastPathComponent()
        func isOccupied(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
                || (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
        }
        guard FileManager.default.fileExists(atPath: parent.path), !isOccupied(output) else {
            throw SongError.invalid("保存先フォルダがないか、同名の曲ファイルが既にあります。上書きしません。")
        }

        if args.count == 4 {
            let model = args[3]
            let provider = OllamaProvider(model: model, disableThinking: true)
            let pronunciation = OllamaPronunciationProvider(model: model)
            let service = LinguisticAnalysisService()
            for (index, phrase) in song.phrases.enumerated() {
                var meaningDone = false
                for attempt in 1...2 {
                    do {
                        let request = LinguisticAnalysisRequest(document: song, phrase: phrase)
                        let analysis = try await provider.analyze(request: request)
                        guard !analysis.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              analysis.words.allSatisfy({ !$0.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                            throw ProviderError.malformedResponse
                        }
                        song = try service.apply(analysis, request: request, source: provider.source, to: song)
                        meaningDone = true
                        break
                    } catch {
                        if attempt == 2 {
                            throw SongError.invalid("\(index + 1)行目の意味・訳を解析できませんでした: \(error.localizedDescription)")
                        }
                    }
                }
                guard meaningDone else { throw SongError.invalid("意味・訳の解析が完了しませんでした。") }
                for attempt in 1...2 {
                    do {
                        song = try await pronunciation.annotate(phrase: phrase, in: song)
                        break
                    } catch {
                        if attempt == 2 {
                            throw SongError.invalid("\(index + 1)行目のIPA・カタカナを解析できませんでした: \(error.localizedDescription)")
                        }
                    }
                }
                fputs("Annotated line \(index + 1)/\(song.phrases.count)\n", stderr)
            }
            song.metadata.notes += " 日本語訳・語義・IPA・カタカナ読みはローカルOllama（\(model)）による未校正の候補。"
        }

        guard !isOccupied(output) else {
            throw SongError.invalid("保存先フォルダがないか、同名の曲ファイルが既にあります。上書きしません。")
        }
        let temporary = parent.appendingPathComponent(".\(output.lastPathComponent).tmp-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            try song.encoded().write(to: temporary.appendingPathComponent("document.json"), options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: output)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        struct Result: Encodable { let path: String; let phrases: Int; let words: Int; let syllables: Int }
        let result = Result(path: output.path, phrases: song.phrases.count,
                            words: song.words.count, syllables: song.syllables.count)
        print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
    }
}
