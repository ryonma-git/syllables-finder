import Foundation

/// Value snapshots make FileDocument background saves independent of mutable FileWrappers.
public struct DocumentPackage: Sendable {
    public var song: SongDocument
    private var attachments: [String: PackageEntry]
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
            guard !file.isSymbolicLink, depth <= 16, count <= 10_000 else {
                throw SongError.invalid("文書内に対応できないファイル構造があります。")
            }
            if file.isRegularFile, let data = file.regularFileContents {
                bytes += data.count
                guard bytes <= 100_000_000 else { throw SongError.invalid("添付資料が大きすぎます（上限100MB）。") }
                return .file(data)
            }
            guard let entries = file.fileWrappers else { throw SongError.invalid("添付資料を読み取れません。") }
            var result: [String: PackageEntry] = [:]
            for (name, child) in entries {
                guard name != ".", name != "..", !name.contains("/") else { throw SongError.invalid("添付資料の名前が不正です。") }
                result[name] = try snapshot(child, depth: depth + 1)
            }
            return .directory(result)
        }
        var entries: [String: PackageEntry] = [:]
        for (name, child) in children {
            guard name != ".", name != "..", !name.contains("/") else { throw SongError.invalid("添付資料の名前が不正です。") }
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
        guard let name = path.last, !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }),
              name != "document.json" || path.count > 1 else {
            throw SongError.invalid("添付資料の名前が不正です。")
        }
        func insert(_ entries: inout [String: PackageEntry], _ remaining: ArraySlice<String>) {
            let head = remaining.first!
            if remaining.count == 1 { entries[head] = .file(data); return }
            var children: [String: PackageEntry] = [:]
            if case .directory(let existing)? = entries[head] { children = existing }
            insert(&children, remaining.dropFirst())
            entries[head] = .directory(children)
        }
        insert(&attachments, path[...])
    }

    public func fileWrapper() throws -> FileWrapper {
        var files = attachments.mapValues { $0.wrapper() }
        files["document.json"] = FileWrapper(regularFileWithContents: try song.encoded())
        return FileWrapper(directoryWithFileWrappers: files)
    }
}
