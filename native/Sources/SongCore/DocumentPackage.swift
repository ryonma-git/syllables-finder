import Foundation

/// Value snapshots make FileDocument background saves independent of mutable FileWrappers.
public struct DocumentPackage: Sendable {
    public var song: SongDocument
    private var attachments: [String: PackageEntry]
    private static let maximumBytes = 100_000_000
    private static let maximumEntries = 10_000
    private static let maximumDepth = 16
    private indirect enum PackageEntry: Sendable {
        case file(Data)
        case directory([String: PackageEntry])
        func wrapper() -> FileWrapper {
            switch self {
            case .file(let data): FileWrapper(regularFileWithContents: data)
            case .directory(let files): FileWrapper(directoryWithFileWrappers: files.mapValues { $0.wrapper() })
            }
        }
    }

    public init(song: SongDocument = .init()) { self.song = song; attachments = [:] }
    public init(reading wrapper: FileWrapper) throws {
        guard wrapper.isDirectory, var children = wrapper.fileWrappers,
              let documentFile = children.removeValue(forKey: "document.json"), documentFile.isRegularFile,
              let content = documentFile.regularFileContents else {
            throw SongError.invalid("songproj内にdocument.jsonが見つかりません。")
        }
        var count = 0
        var bytes = content.count
        func snapshot(_ file: FileWrapper, depth: Int) throws -> PackageEntry {
            count += 1
            guard !file.isSymbolicLink, depth <= Self.maximumDepth, count <= Self.maximumEntries else {
                throw SongError.invalid("文書内に対応できないファイル構造があります。")
            }
            if file.isRegularFile, let data = file.regularFileContents {
                guard data.count <= Self.maximumBytes - bytes else { throw SongError.invalid("添付資料が大きすぎます（上限100MB）。") }
                bytes += data.count
                return .file(data)
            }
            guard let entries = file.fileWrappers else { throw SongError.invalid("添付資料を読み取れません。") }
            var result: [String: PackageEntry] = [:]
            for (name, child) in entries {
                guard Self.validName(name) else { throw SongError.invalid("添付資料の名前が不正です。") }
                result[name] = try snapshot(child, depth: depth + 1)
            }
            return .directory(result)
        }
        var entries: [String: PackageEntry] = [:]
        for (name, child) in children {
            guard Self.validName(name) else { throw SongError.invalid("添付資料の名前が不正です。") }
            entries[name] = try snapshot(child, depth: 0)
        }
        let (document, migratedFrom) = try SongDocument.decodeReportingMigration(content)
        song = document
        if let version = migratedFrom {
            // Keep the pre-migration file once; a later save must not replace the original backup.
            var preserved: [String: PackageEntry] = [:]
            if case .directory(let existing)? = entries["preserved"] { preserved = existing }
            let name = "document-v\(version).json"
            if preserved[name] == nil { preserved[name] = .file(content) }
            entries["preserved"] = .directory(preserved)
        }
        // Migration may add an original-file backup; budget the form that will actually be saved.
        try Self.validate(entries, documentBytes: song.encoded().count)
        attachments = entries
    }
    /// Relative paths of attached files, for diagnostics and tests.
    public var attachmentPaths: [String] {
        func walk(_ prefix: String, _ entries: [String: PackageEntry]) -> [String] {
            entries.flatMap { name, entry -> [String] in
                if case .directory(let children) = entry { return walk(prefix + name + "/", children) }
                return [prefix + name]
            }
        }
        return walk("", attachments).sorted()
    }

    /// Adds or replaces an attached source file (for example an imported MIDI file).
    public mutating func attach(_ data: Data, at path: [String]) throws {
        guard let name = path.last, !path.isEmpty, path.allSatisfy(Self.validName),
              name != "document.json" || path.count > 1 else {
            throw SongError.invalid("添付資料の名前が不正です。")
        }
        guard path.count <= Self.maximumDepth + 1 else { throw SongError.invalid("文書内に対応できないファイル構造があります。") }
        func insert(_ entries: inout [String: PackageEntry], _ remaining: ArraySlice<String>) {
            let head = remaining.first!
            if remaining.count == 1 { entries[head] = .file(data); return }
            var children: [String: PackageEntry] = [:]
            if case .directory(let existing)? = entries[head] { children = existing }
            insert(&children, remaining.dropFirst())
            entries[head] = .directory(children)
        }
        var candidate = attachments
        insert(&candidate, path[...])
        try Self.validate(candidate, documentBytes: song.encoded().count)
        attachments = candidate
    }

    public func fileWrapper() throws -> FileWrapper {
        let document = try song.encoded()
        try Self.validate(attachments, documentBytes: document.count)
        var files = attachments.mapValues { $0.wrapper() }
        files["document.json"] = FileWrapper(regularFileWithContents: document)
        return FileWrapper(directoryWithFileWrappers: files)
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    /// Share the reader's limits with attachment changes and saves, before publishing a new package.
    private static func validate(_ entries: [String: PackageEntry], documentBytes: Int) throws {
        var count = 0
        var bytes = documentBytes
        func walk(_ entries: [String: PackageEntry], depth: Int) throws {
            for (name, entry) in entries {
                count += 1
                guard validName(name), depth <= maximumDepth, count <= maximumEntries else {
                    throw SongError.invalid("文書内に対応できないファイル構造があります。")
                }
                switch entry {
                case .file(let data):
                    guard data.count <= maximumBytes - bytes else { throw SongError.invalid("添付資料が大きすぎます（上限100MB）。") }
                    bytes += data.count
                case .directory(let children): try walk(children, depth: depth + 1)
                }
            }
        }
        guard bytes <= maximumBytes else { throw SongError.invalid("添付資料が大きすぎます（上限100MB）。") }
        try walk(entries, depth: 0)
    }
}
