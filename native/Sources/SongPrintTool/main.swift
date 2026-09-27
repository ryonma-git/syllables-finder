import Foundation
import SongCore
import SongPrint

@main
@MainActor
struct SongPrintTool {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3,
              let sample = SampleCatalog.entries.first(where: { $0.id == arguments[1] }) else {
            throw PrintError.creationFailed
        }
        let output = URL(fileURLWithPath: arguments[2])
        let sheet = PrintSheet(song: sample.make())
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
