import SwiftUI
import SongCore
import UniformTypeIdentifiers

extension UTType {
    static let songProject = UTType(exportedAs: "org.syllablesfinder.songproj", conformingTo: .package)
}

struct SongFile: FileDocument {
    static var readableContentTypes: [UTType] { [.songProject] }
    var package: DocumentPackage
    var song: SongDocument {
        get { package.song }
        set { package.song = newValue }
    }
    init(song: SongDocument = .init()) { package = .init(song: song) }
    init(configuration: ReadConfiguration) throws { package = try .init(reading: configuration.file) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try package.fileWrapper() }
}

@main
struct SingingWorkspaceApp: App {
    @StateObject private var displayPreferences = DisplayPreferences()

    var body: some Scene {
        DocumentGroup(newDocument: SongFile()) { configuration in
            WorkspaceView(file: configuration.$document)
                .environmentObject(displayPreferences)
        }
        .defaultSize(width: 1180, height: 790)

        Settings {
            DisplaySettingsView(preferences: displayPreferences)
        }
    }
}
