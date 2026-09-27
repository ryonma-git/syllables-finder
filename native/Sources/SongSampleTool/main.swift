import Foundation
import SongCore

let twinkle = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--twinkle"
guard CommandLine.arguments.count == 2 || twinkle else {
    fputs("Usage: SongSampleTool [--twinkle] /absolute/path/Sample.songproj\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments.last!)
guard url.pathExtension == "songproj", !FileManager.default.fileExists(atPath: url.path) else {
    fputs("Choose a new .songproj path; existing files are never overwritten.\n", stderr)
    exit(2)
}
do {
    let song = twinkle ? TwinkleSample.make() : SampleSongDocument.make()
    let json = try song.encoded()
    let midi = twinkle ? try SampleMIDI.encode(song) : nil
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    try json.write(to: url.appendingPathComponent("document.json"), options: .atomic)
    if let midi {
        let source = url.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try midi.write(to: source.appendingPathComponent("Twinkle.mid"), options: .atomic)
    }
    print(url.path)
} catch {
    fputs("Sample creation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
