import Foundation
import SongCore

let arguments = CommandLine.arguments
let twinkle = arguments.count == 3 && arguments[1] == "--twinkle"
let namedSample = arguments.count == 4 && arguments[1] == "--sample"
guard arguments.count == 2 || twinkle || namedSample else {
    fputs("Usage: SongSampleTool [--twinkle | --sample ID] /absolute/path/Sample.songproj\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: arguments.last!)
guard url.pathExtension == "songproj", !FileManager.default.fileExists(atPath: url.path) else {
    fputs("Choose a new .songproj path; existing files are never overwritten.\n", stderr)
    exit(2)
}
do {
    let song: SongDocument
    if namedSample {
        guard let entry = SampleCatalog.entries.first(where: { $0.id == arguments[2] }) else {
            fputs("Unknown sample ID: \(arguments[2])\n", stderr)
            exit(2)
        }
        song = entry.make()
    } else {
        song = twinkle ? TwinkleSample.make() : SampleSongDocument.make()
    }
    let json = try song.encoded()
    let midi = twinkle || (namedSample && arguments[2] == "twinkle") ? try SampleMIDI.encode(song) : nil
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
