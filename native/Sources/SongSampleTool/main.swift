import Foundation
import SongCore

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: SongSampleTool /absolute/path/Sample.songproj\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard url.pathExtension == "songproj", !FileManager.default.fileExists(atPath: url.path) else {
    fputs("Choose a new .songproj path; existing files are never overwritten.\n", stderr)
    exit(2)
}
do {
    let json = try SampleSongDocument.make().encoded()
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    try json.write(to: url.appendingPathComponent("document.json"), options: .atomic)
    print(url.path)
} catch {
    fputs("Sample creation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
