import SwiftUI
import UniformTypeIdentifiers
import SongCore

struct WorksheetFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var song: SongDocument
    init(song: SongDocument = .init()) { self.song = song }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        song = try SongDocument.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try song.encoded())
    }
}

@main
struct SingingWorksheetApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: WorksheetFile()) { file in
            WorksheetView(file: file.$document)
        }
        .defaultSize(width: 1000, height: 690)
    }
}
