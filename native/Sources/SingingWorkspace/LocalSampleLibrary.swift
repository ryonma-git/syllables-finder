import Foundation
import SongCore

/// Songs kept on this Mac, outside the public sample catalog and Git repository.
struct LocalSample: Identifiable {
    let url: URL
    let song: SongDocument
    var id: URL { url }
    var title: String { song.metadata.title }
    var languageName: String { Syllabifier.displayName(for: song.metadata.sourceLanguage) }
    var subtitle: String {
        let notes = song.music.events.filter { $0.note != nil }.count
        return song.words.isEmpty ? "旋律\(notes)音・歌詞未登録" : "旋律\(notes)音・歌詞あり"
    }
}

enum LocalSampleLibrary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SingingWorkspace/LocalSamples", isDirectory: true)
    }

    static func entries() -> [LocalSample] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                                options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "songproj", let package = try? read(url) else { return nil }
            return LocalSample(url: url, song: package.song)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @discardableResult
    static func add(_ source: URL) throws -> URL {
        guard source.pathExtension == "songproj" else { throw SongError.invalid("歌唱練習ドキュメントを選んでください。") }
        _ = try read(source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent(base).appendingPathExtension("songproj")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base)-\(suffix)").appendingPathExtension("songproj")
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private static func read(_ url: URL) throws -> DocumentPackage {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SongError.invalid("歌唱練習ドキュメントを読み込めません。")
        }
        return try DocumentPackage(reading: FileWrapper(url: url, options: .immediate))
    }
}
