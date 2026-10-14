import Foundation
import SongCore
import SongPrint

@main
@MainActor
struct SongPrintTool {
    static func main() throws {
        let arguments = CommandLine.arguments
        let options = Array(arguments.dropFirst(3))
        guard arguments.count >= 3,
              options.allSatisfy({ $0 == "--stage-german" || $0 == "--meaning-below" ||
                  $0.hasPrefix("--order=") || $0.hasPrefix("--design=") ||
                  $0.hasPrefix("--accent=") || $0.hasPrefix("--vowel=") }),
              ["--order=", "--design=", "--accent=", "--vowel="].allSatisfy({ prefix in
                  options.filter { $0.hasPrefix(prefix) }.count <= 1
              }) else {
            throw PrintError.creationFailed
        }
        var song: SongDocument
        if arguments[1].hasSuffix(".songproj") {
            let source = URL(fileURLWithPath: arguments[1], isDirectory: true)
                .appendingPathComponent("document.json")
            song = try SongDocument.decode(Data(contentsOf: source))
        } else if let sample = SampleCatalog.entries.first(where: { $0.id == arguments[1] }) {
            song = sample.make()
        } else {
            throw PrintError.creationFailed
        }
        let output = URL(fileURLWithPath: arguments[2])
        if options.contains("--stage-german") {
            guard NinthPronunciation.isAvailable(in: song) else { throw PrintError.creationFailed }
            NinthPronunciation.apply(.stage, to: &song)
        }
        let order: ReadingOrder
        if let option = options.first(where: { $0.hasPrefix("--order=") }) {
            let names = option.dropFirst("--order=".count).split(separator: ",")
            guard let parsed = ReadingOrder(names.compactMap { ReadingElement(rawValue: String($0)) }) else {
                throw PrintError.creationFailed
            }
            order = parsed
        } else { order = options.contains("--meaning-below") ? .meaningBelow : .baseline }
        var appearance = PrintAppearance()
        if let value = options.first(where: { $0.hasPrefix("--design=") }) {
            guard let design = PrintDesign(rawValue: String(value.dropFirst("--design=".count))) else {
                throw PrintError.creationFailed
            }
            appearance.design = design
        }
        if let value = options.first(where: { $0.hasPrefix("--accent=") }) {
            guard let color = PrintRGBColor(hex: String(value.dropFirst("--accent=".count))) else {
                throw PrintError.creationFailed
            }
            appearance.accent = color
        }
        if let value = options.first(where: { $0.hasPrefix("--vowel=") }) {
            guard let color = PrintRGBColor(hex: String(value.dropFirst("--vowel=".count))) else {
                throw PrintError.creationFailed
            }
            appearance.vowelNucleus = color
        }
        let sheet = PrintSheet(song: song, order: order, appearance: appearance)
        let data: Data
        switch output.pathExtension.lowercased() {
        case "pdf": data = try PDFSheet.render(sheet)
        case "docx": data = try WordSheet.render(sheet)
        default: throw PrintError.creationFailed
        }
        try data.write(to: output, options: .atomic)
        print(output.path)
    }
}
