import CoreGraphics
import Foundation
import ImageIO
import SongCore
import SongNotation
import UniformTypeIdentifiers

/// Score output for review and for the user's own material.
///   SongStaffTool <sample-id | Song.songproj> out.(pdf|png)
///   SongStaffTool --lyrics lyrics.txt --language en --midi song.mid [--track N[,N…]] [--grid 0.25|none]
///                 [--title T] [--songproj out.songproj] out.(pdf|png)
/// Lyrics are one line per phrase; the MIDI file provides the melody. Nothing is sent anywhere.
let arguments = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(2) }
guard let output = arguments.last, arguments.count >= 2 else {
    fail("Usage: SongStaffTool <sample-id | Song.songproj> out.pdf\n       SongStaffTool --lyrics lyrics.txt --language en --midi song.mid [--track N[,N…]] [--grid 0.25|none] [--title T] [--songproj out.songproj] out.pdf")
}
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count - 1 else { return nil }
    return arguments[index + 1]
}

var song: SongDocument
if let lyricsPath = option("--lyrics") {
    let language = option("--language") ?? "en"
    guard Syllabifier.supports(language) else { fail("Unsupported language \(language). Use: \(Syllabifier.languages.map(\.id).joined(separator: ", "))") }
    let lyrics = try String(contentsOf: URL(fileURLWithPath: lyricsPath), encoding: .utf8)
    song = SongDocument()
    song.metadata.title = option("--title") ?? URL(fileURLWithPath: lyricsPath).deletingPathExtension().lastPathComponent
    song.metadata.sourceLanguage = language
    var section = 0
    for line in lyrics.components(separatedBy: .newlines) {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            // A blank line starts a new section (verse), as on the old Tk sheets.
            if !(song.sections.last?.phraseIDs.isEmpty ?? true) { section += 1; song.sections.append(.init(title: "第\(section + 1)節")) }
            continue
        }
        song.appendPhrase(text: line, language: language, syllabify: true)
    }
    song.sections.removeAll { $0.phraseIDs.isEmpty }
    if let midiPath = option("--midi") {
        let parsed = try MIDIFileImport.parse(Data(contentsOf: URL(fileURLWithPath: midiPath)))
        for (index, candidate) in parsed.candidates.enumerated() {
            print("track \(index): \(candidate.name) · \(candidate.notes.count) notes\(candidate.isPolyphonic ? " · chords" : "")")
        }
        let chosen: [Int]
        if let tracks = option("--track") { chosen = tracks.split(separator: ",").compactMap { Int($0) } }
        else {
            // The vocal line is usually the monophonic candidate with the most notes.
            let melodic = parsed.candidates.filter { !$0.isPolyphonic }
            guard let best = (melodic.isEmpty ? parsed.candidates : melodic).max(by: { $0.notes.count < $1.notes.count }) else { fail("No notes in the MIDI file.") }
            chosen = [best.id]
        }
        let gridText = option("--grid") ?? "0.25"
        let grid: Beat? = gridText == "none" ? nil : try Beat.grid(Double(gridText) ?? 0.25, divisions: 48)
        _ = try parsed.apply(to: &song, candidateIDs: chosen, replace: true, grid: grid)
        print("parts from tracks \(chosen); diagnostics: \(parsed.diagnostics.count)")
        for part in song.music.parts {
            let proposal = try LyricAligner.propose(song: song, partID: part.id)
            LyricAligner.apply(proposal, to: &song)
            print("aligned \(part.name): \(proposal.syllableCount) syllables, \(proposal.sungNoteCount) sung notes, "
                  + "\(proposal.melismaCount) melismas, \(proposal.elisionCount) elisions, \(proposal.issues.count) places to check")
        }
    }
    try song.validate()
    if let path = option("--songproj") {
        let url = URL(fileURLWithPath: path)
        guard !FileManager.default.fileExists(atPath: url.path) else { fail("\(path) exists; choose a new path.") }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try song.encoded().write(to: url.appendingPathComponent("document.json"))
        if let midiPath = option("--midi") {
            let source = url.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: midiPath), to: source.appendingPathComponent(URL(fileURLWithPath: midiPath).lastPathComponent))
        }
        print(url.path)
    }
} else if arguments[0].hasSuffix(".songproj") {
    song = try SongDocument.decode(Data(contentsOf: URL(fileURLWithPath: arguments[0]).appendingPathComponent("document.json")))
} else if let entry = SampleCatalog.entries.first(where: { $0.id == arguments[0] }) {
    song = entry.make()
} else {
    fail("Unknown sample. Available: \(SampleCatalog.entries.map(\.id).joined(separator: ", "))")
}

let sheet = ScoreSheet(song: song)
let url = URL(fileURLWithPath: output)
if url.pathExtension.lowercased() == "pdf" {
    try sheet.pdfData().write(to: url, options: .atomic)
    print(url.path, "(\(sheet.pageCount) pages)")
} else {
    for page in 0..<sheet.pageCount {
        let pageURL = page == 0 ? url : url.deletingPathExtension().appendingPathExtension("\(page + 1).png")
        guard let image = sheet.image(page: page),
              let destination = CGImageDestinationCreateWithURL(pageURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
        print(pageURL.path)
    }
}
