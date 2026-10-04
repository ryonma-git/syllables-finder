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
              options.allSatisfy({ $0 == "--stage-german" || $0 == "--meaning-below" || $0.hasPrefix("--order=") }),
              options.filter({ $0.hasPrefix("--order=") }).count <= 1 else {
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
        let sheet = PrintSheet(song: song, order: order)
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
