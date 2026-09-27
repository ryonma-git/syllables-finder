import CoreGraphics
import Foundation
import ImageIO
import SongCore
import SongNotation
import UniformTypeIdentifiers

/// Renders the staff view of a sample or a .songproj to PNG for visual review.
/// Usage: SongStaffTool <sample-id | /path/Song.songproj> /path/out.png [measuresPerRow]
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fputs("Usage: SongStaffTool <sample-id | Song.songproj> out.png [measuresPerRow]\n", stderr)
    exit(2)
}
let song: SongDocument
if arguments[1].hasSuffix(".songproj") {
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]).appendingPathComponent("document.json"))
    song = try SongDocument.decode(data)
} else if let entry = SampleCatalog.entries.first(where: { $0.id == arguments[1] }) {
    song = entry.make()
} else {
    fputs("Unknown sample. Available: \(SampleCatalog.entries.map(\.id).joined(separator: ", "))\n", stderr)
    exit(2)
}
let perRow = arguments.count > 3 ? max(1, Int(arguments[3]) ?? 4) : 4
let image = ScorePreview(song: song, measuresPerRow: perRow).render()
let url = URL(fileURLWithPath: arguments[2])
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print(url.path)

struct ScorePreview {
    let song: SongDocument
    let measuresPerRow: Int
    let width = 1100.0
    let space = 11.0
    let lyricFont = "HiraginoSans-W3"

    func render() -> CGImage {
        let slices = MeasureProjection(song: song).slices
        let rows = stride(from: 0, to: slices.count, by: measuresPerRow).map { Array(slices[$0..<min($0 + measuresPerRow, slices.count)]) }
        let parts = StaffParts(song: song)
        let headerMeter = song.music.meters.first
        let header = StaffEngraving.headerWidth(space: space, meter: headerMeter)
        let left = 24 + header
        let maxBeats = rows.map { ($0.last!.range.end.doubleValue - $0.first!.range.start.doubleValue) }.max() ?? 4
        let scale = (width - left - 24) / max(1, maxBeats)
        let songEnd = MeasureProjection.songEnd(song).doubleValue
        let paddings = parts.map { StaffEngraving.padding(positions: $0.positions(song: song)) }
        let lyricBlock = 30.0
        let staffBlocks = paddings.map { ($0.above + 4 + $0.below) * space + lyricBlock }
        let rowHeight = staffBlocks.reduce(0, +) + 24
        let height = 40 + Double(rows.count) * rowHeight
        let scaleFactor = 2.0
        let context = CGContext(data: nil, width: Int(width * scaleFactor), height: Int(height * scaleFactor), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width * scaleFactor, height: height * scaleFactor))
        context.translateBy(x: 0, y: height * scaleFactor)
        context.scaleBy(x: scaleFactor, y: -scaleFactor)
        let ink = CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        let accent = CGColor(red: 0.0, green: 0.45, blue: 0.5, alpha: 1)
        if let title = StaffPainter.textPath(song.metadata.title, font: "HiraginoSans-W6", size: 16, x: 24, baseline: 26) {
            context.addPath(title.path); context.setFillColor(ink); context.fillPath()
        }
        var top = 40.0
        for (rowIndex, row) in rows.enumerated() {
            let start = row.first!.range.start.doubleValue
            func x(_ beat: Double) -> Double { left + (beat - start) * scale }
            let lineEnd = x(row.last!.range.end.doubleValue)
            var staffY = top
            for (partIndex, part) in parts.enumerated() {
                let staffTop = staffY + paddings[partIndex].above * space
                let projection = NotationProjection(song: song, measures: row, including: part.include)
                let engraving = StaffEngraving(pieces: projection.pieces, measures: row, meters: song.music.meters, clef: part.clef,
                                               space: space, staffTop: staffTop, lineStart: left - header, lineEnd: lineEnd,
                                               headerX: left - header, headerMeter: rowIndex == 0 ? headerMeter : nil,
                                               songEnd: songEnd, x: x)
                StaffPainter.draw(engraving, in: context, color: ink)
                if let issue = projection.issue, let text = StaffPainter.textPath(issue, font: lyricFont, size: 10, x: left, baseline: staffTop - 4) {
                    context.addPath(text.path); context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0, alpha: 1)); context.fillPath()
                }
                if parts.count > 1, let label = StaffPainter.textPath(part.name, font: lyricFont, size: 9, x: 4, baseline: staffTop + 2 * space + 3) {
                    context.addPath(label.path); context.setFillColor(accent); context.fillPath()
                }
                let baseline = staffTop + (4 + paddings[partIndex].below) * space + 14
                let range = BeatRange(start: row.first!.range.start, end: row.last!.range.end)
                let items = LyricLayout.items(song: song, range: range, include: part.include, headLeft: engraving.headLeft, x: x,
                                              noteEnd: { engraving.headRight[$0] }, measure: { StaffPainter.textWidth($0, font: lyricFont, size: 12) })
                for item in items {
                    if let text = StaffPainter.textPath(item.text, font: lyricFont, size: 12 * item.fontScale, x: item.x, baseline: baseline) {
                        context.addPath(text.path); context.setFillColor(ink); context.fillPath()
                    }
                    if let hyphen = item.hyphen {
                        let mid = (hyphen.from + hyphen.to) / 2
                        context.fill(CGRect(x: mid - 3, y: baseline - 4.5, width: 6, height: 1.1))
                    }
                    if let extender = item.extender {
                        context.fill(CGRect(x: extender.from, y: baseline, width: extender.to - extender.from, height: 1))
                    }
                }
                staffY += staffBlocks[partIndex]
            }
            if parts.count > 1 {
                let firstTop = top + paddings[0].above * space
                let lastTop = staffY - staffBlocks.last! + paddings.last!.above * space
                context.setFillColor(ink)
                context.fill(CGRect(x: left - header - 4, y: firstTop, width: 3, height: lastTop + 4 * space - firstTop))
            }
            if let number = StaffPainter.textPath(row.first!.number, font: lyricFont, size: 9, x: left - header, baseline: top + paddings[0].above * space - 6) {
                context.addPath(number.path); context.setFillColor(accent); context.fillPath()
            }
            top += rowHeight
        }
        return context.makeImage()!
    }
}

/// The staves to draw: one per part, or a single staff for documents without parts.
struct StaffPart {
    let name: String
    let clef: Clef
    let include: (MusicalEvent) -> Bool
    func positions(song: SongDocument) -> [Int] {
        song.music.events.filter(include).compactMap { $0.note?.pitch }.map { StaffEngraving.position(pitch: $0, clef: clef) }
    }
}

func StaffParts(song: SongDocument) -> [StaffPart] {
    if song.music.parts.isEmpty { return [StaffPart(name: "旋律", clef: .treble, include: { _ in true })] }
    return song.music.parts.map { part in
        let id = part.id
        return StaffPart(name: part.abbreviation.isEmpty ? part.name : part.abbreviation, clef: part.clef, include: { $0.partID == id })
    }
}
