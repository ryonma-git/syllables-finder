import Foundation
import SongCore
import SongPrint

@main
@MainActor
struct SongPrintTool {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw PrintError.creationFailed
        }
        let song: SongDocument
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
        let sheet = PrintSheet(song: song)
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
