import CoreGraphics
import CoreText
import Foundation
import SongCore

/// A printable score: systems of measures (one staff per part, lyrics beneath) laid out on A4 pages.
/// Measures are grouped so that each one gets the width its notes and lyrics need, then each
/// system is justified to the line width. Positions inside a system stay proportional to beats.
public struct ScoreSheet {
    public struct Options: Sendable {
        public var showReading = true
        public var showIPA = false
        public var showTranslation = true
        public var pageSize = CGSize(width: 595.28, height: 841.89) // ISO A4 in points
        public var margin = 40.0
        public var space = 5.6            // staff space in points (staff height 22.4 pt)
        public var lyricSize = 9.5
        public init() {}
    }

    struct Staff {
        let name: String
        let abbreviation: String
        let clef: Clef
        let include: @Sendable (MusicalEvent) -> Bool
        let padding: (above: Double, below: Double)
    }

    struct System {
        let measures: [MeasureSlice]
        let scale: Double
        let height: Double
    }

    public let song: SongDocument
    public let options: Options
    let staves: [Staff]
    let pages: [[System]]
    let headerWidth: Double
    let songEnd: Double

    static let lyricFont = "HiraginoSans-W3"
    static let boldFont = "HiraginoSans-W6"

    public var pageCount: Int { max(1, pages.count) }

    public init(song: SongDocument, options: Options = .init()) {
        self.song = song
        self.options = options
        let sp = options.space
        let staves: [Staff] = (song.music.parts.isEmpty
                  ? [(name: "旋律", abbreviation: "", clef: Clef.treble, id: UUID?.none)]
                  : song.music.parts.map { (name: $0.name, abbreviation: $0.abbreviation, clef: $0.clef, id: Optional($0.id)) }
        ).map { item in
            let id = item.id
            let include: @Sendable (MusicalEvent) -> Bool = { id == nil || $0.partID == id }
            let positions = song.music.events.filter(include).compactMap { $0.note?.pitch }.map { StaffEngraving.position(pitch: $0, clef: item.clef) }
            return Staff(name: item.name, abbreviation: item.abbreviation, clef: item.clef, include: include,
                         padding: StaffEngraving.padding(positions: positions))
        }
        self.staves = staves
        headerWidth = StaffEngraving.headerWidth(space: sp, meter: song.music.meters.first) + (song.music.parts.count > 1 ? 8 : 0)
        songEnd = MeasureProjection.songEnd(song).doubleValue

        let lineWidth = options.pageSize.width - 2 * options.margin - headerWidth
        let slices = MeasureProjection(song: song).slices
        let needs = slices.map { Self.minimumScale(song: song, measure: $0, staves: staves, options: options) }
        // Line breaking: choose system breaks that keep every system comfortably filled (a small
        // dynamic program, like text justification) instead of greedily filling and leaving a stub.
        let comfortable = 30.0 // points per quarter note when there is room
        let n = slices.count
        func natural(_ i: Int, _ j: Int) -> (beats: Double, need: Double) {
            (slices[i...j].reduce(0) { $0 + $1.range.length }, needs[i...j].max() ?? comfortable)
        }
        var best = Array(repeating: Double.infinity, count: n + 1)
        var breakAt = Array(repeating: 0, count: n + 1)
        best[0] = 0
        if n > 0 {
            for j in 1...n {
                for i in stride(from: j - 1, through: 0, by: -1) {
                    let (beats, need) = natural(i, j - 1)
                    let minimum = beats * need
                    if minimum > lineWidth && j - 1 > i { break }  // too wide; longer spans only get wider
                    let fill = beats * max(need, comfortable) / lineWidth
                    let cost: Double
                    if j == n { cost = fill < 0.45 ? (0.45 - fill) * (0.45 - fill) * 4 : 0 } // a short last system is fine, a stub is not
                    else { cost = (1 - min(fill, 1.2)) * (1 - min(fill, 1.2)) + (fill > 1 ? (fill - 1) * 3 : 0) }
                    if best[i] + cost < best[j] { best[j] = best[i] + cost; breakAt[j] = i }
                }
            }
        }
        var ranges: [ClosedRange<Int>] = []
        var cursor = n
        while cursor > 0 { ranges.insert(breakAt[cursor]...(cursor - 1), at: 0); cursor = breakAt[cursor] }
        var systems: [System] = []
        for range in ranges {
            let (beats, need) = natural(range.lowerBound, range.upperBound)
            let isLast = range.upperBound == n - 1
            let naturalWidth = beats * max(need, comfortable)
            // Justify full systems; a short last system keeps a natural width.
            let scale = isLast && naturalWidth < lineWidth * 0.75 ? max(need, comfortable) : lineWidth / max(beats, 0.25)
            systems.append(.init(measures: Array(slices[range]), scale: scale, height: Self.systemHeight(staves: staves, options: options)))
        }
        // Paginate.
        var pages: [[System]] = []
        var current: [System] = []
        var used = Self.titleHeight
        let available = options.pageSize.height - 2 * options.margin - 18 // footer
        for system in systems {
            if used + system.height > available && !current.isEmpty {
                pages.append(current); current = []; used = 0
            }
            current.append(system); used += system.height
        }
        if !current.isEmpty || pages.isEmpty { pages.append(current) }
        self.pages = pages
    }

    static let titleHeight = 54.0

    static func systemHeight(staves: [Staff], options: Options) -> Double {
        let lyricBlock = options.lyricSize + 6 + (options.showReading ? 9 : 0) + (options.showIPA ? 9 : 0)
        let staffBlocks = staves.reduce(0) { $0 + ($1.padding.above + 4 + $1.padding.below) * options.space + lyricBlock + 4 }
        return staffBlocks + 16 + (options.showTranslation ? 12 : 0)
    }

    /// Smallest points-per-quarter at which this measure's notes and lyrics do not collide.
    static func minimumScale(song: SongDocument, measure: MeasureSlice, staves: [Staff], options: Options) -> Double {
        var need = 18.0
        let sp = options.space
        for staff in staves {
            let events = song.music.events.filter { staff.include($0) && $0.onset >= measure.range.start && $0.onset < measure.range.end }
                .sorted { $0.onset < $1.onset }
            for event in events {
                let duration = max(0.125, event.duration.doubleValue)
                need = max(need, (event.note == nil ? 2.2 : 2.4) * sp / duration)
                // Lyric text that starts on this note must fit before the next note.
                let syllables = song.alignments.filter { alignment in
                    alignment.musicTargets.first.map { if case .event(let id, _) = $0 { id == event.id } else { false } } ?? false
                }.flatMap(\.languageTargets).compactMap { song.syllable($0.id)?.text.value }
                if !syllables.isEmpty {
                    let width = StaffPainter.textWidth(syllables.joined(separator: "‿"), font: lyricFont, size: options.lyricSize) + 7
                    need = max(need, width / duration)
                }
            }
        }
        return min(need, 400)
    }

    // MARK: Output

    public func pdfData() throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw SongError.invalid("PDFを作成できませんでした。") }
        var box = CGRect(origin: .zero, size: options.pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: song.metadata.title, kCGPDFContextCreator: "Singing Workspace"]
        guard let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else {
            throw SongError.invalid("PDFを作成できませんでした。")
        }
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: options.pageSize.height)
            context.scaleBy(x: 1, y: -1)
            draw(page: page, in: context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Renders one page to an image (for previews and visual checks).
    public func image(page: Int, scale: Double = 2) -> CGImage? {
        let width = Int(options.pageSize.width * scale), height = Int(options.pageSize.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: Double(height))
        context.scaleBy(x: scale, y: -scale)
        draw(page: page, in: context)
        return context.makeImage()
    }

    /// Draws a page into a y-down context.
    public func draw(page: Int, in context: CGContext) {
        let ink = CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        let muted = CGColor(red: 0.38, green: 0.38, blue: 0.42, alpha: 1)
        let accent = CGColor(red: 0.0, green: 0.42, blue: 0.47, alpha: 1)
        let left = options.margin, right = options.pageSize.width - options.margin
        var y = options.margin
        if page == 0 {
            text(song.metadata.title, font: Self.boldFont, size: 17, x: left, baseline: y + 18, color: ink, in: context)
            var details: [String] = []
            if let language = Syllabifier.languages.first(where: { $0.id == song.metadata.sourceLanguage })?.name { details.append(language) }
            if song.music.parts.count > 1 { details.append(song.music.parts.map(\.name).joined(separator: "・")) }
            if let tempo = song.music.tempos.first { details.append("♩ = \(Int(tempo.bpm.rounded()))") }
            text(details.joined(separator: "　"), font: Self.lyricFont, size: 8.5, x: left, baseline: y + 34, color: muted, in: context)
            y += Self.titleHeight
        }
        let sp = options.space
        for (systemIndex, system) in (page < pages.count ? pages[page] : []).enumerated() {
            let start = system.measures.first!.range.start.doubleValue
            let musicLeft = left + headerWidth
            func x(_ beat: Double) -> Double { musicLeft + (beat - start) * system.scale }
            let lineEnd = x(system.measures.last!.range.end.doubleValue)
            let firstOfSong = system.measures.first!.range.start == .zero
            var staffY = y
            var firstTop = 0.0, lastTop = 0.0
            let range = BeatRange(start: system.measures.first!.range.start, end: system.measures.last!.range.end)
            for (staffIndex, staff) in staves.enumerated() {
                let staffTop = staffY + staff.padding.above * sp
                if staffIndex == 0 { firstTop = staffTop }
                lastTop = staffTop
                let projection = NotationProjection(song: song, measures: system.measures, including: staff.include)
                let lineStart = left + (staves.count > 1 ? 8 : 0)
                let engraving = StaffEngraving(pieces: projection.pieces, measures: system.measures, meters: song.music.meters,
                                               clef: staff.clef, space: sp, staffTop: staffTop, lineStart: lineStart, lineEnd: lineEnd,
                                               headerX: lineStart, headerMeter: firstOfSong ? song.music.meters.first : nil,
                                               songEnd: songEnd, x: x)
                if let issue = projection.issue {
                    // Not engravable as one voice (chords or very short values): say so instead of guessing.
                    for line in 0..<5 { context.setFillColor(ink); context.fill(CGRect(x: lineStart, y: staffTop + Double(line) * sp - 0.3, width: lineEnd - lineStart, height: 0.6)) }
                    text(issue, font: Self.lyricFont, size: 7.5, x: musicLeft + 4, baseline: staffTop + 2.4 * sp, color: CGColor(red: 0.75, green: 0.35, blue: 0, alpha: 1), in: context)
                } else {
                    StaffPainter.draw(engraving, in: context, color: ink)
                }
                if staves.count > 1 {
                    text(staff.abbreviation.isEmpty ? String(staff.name.prefix(2)) : staff.abbreviation, font: Self.boldFont, size: 7,
                         x: left - 2, baseline: staffTop - 2.2, color: accent, in: context)
                }
                if staffIndex == 0 {
                    text(system.measures.first!.number, font: Self.lyricFont, size: 7, x: lineStart + 2, baseline: staffTop - (staves.count > 1 ? 10 : 3),
                         color: muted, in: context)
                }
                // Lyrics, hyphens and extenders under the staff.
                let baseline = staffTop + (4 + staff.padding.below) * sp + options.lyricSize + 2
                let size = options.lyricSize
                let items = LyricLayout.items(song: song, range: range, include: staff.include, headLeft: engraving.headLeft, x: x,
                                              noteEnd: { engraving.headRight[$0] },
                                              measure: { StaffPainter.textWidth($0, font: Self.lyricFont, size: size) })
                for item in items {
                    text(item.text, font: Self.lyricFont, size: size * item.fontScale, x: item.x, baseline: baseline, color: ink, in: context)
                    context.setFillColor(ink)
                    if let hyphen = item.hyphen {
                        let mid = (hyphen.from + hyphen.to) / 2, half = min(2.6, (hyphen.to - hyphen.from) / 2 - 0.5)
                        if half > 0.5 { context.fill(CGRect(x: mid - half, y: baseline - size * 0.33, width: 2 * half, height: 0.7)) }
                    }
                    if let extender = item.extender {
                        context.fill(CGRect(x: extender.from, y: baseline + 0.8, width: extender.to - extender.from, height: 0.6))
                    }
                    let syllables = item.syllableIDs.compactMap { song.syllable($0) }
                    var line = baseline
                    if options.showReading {
                        line += 9
                        let reading = syllables.map(\.reading.value).filter { !$0.isEmpty }.joined(separator: "‿")
                        if !reading.isEmpty { text(reading, font: Self.lyricFont, size: 6.5 * max(0.8, item.fontScale), x: item.x, baseline: line, color: muted, in: context) }
                    }
                    if options.showIPA {
                        line += 9
                        let ipa = syllables.map(\.ipa.value).filter { !$0.isEmpty }.joined(separator: "‿")
                        if !ipa.isEmpty { text("/\(ipa)/", font: "Helvetica", size: 6.5 * max(0.8, item.fontScale), x: item.x, baseline: line, color: muted, in: context) }
                    }
                }
                staffY += (staff.padding.above + 4 + staff.padding.below) * sp + options.lyricSize + 6
                    + (options.showReading ? 9 : 0) + (options.showIPA ? 9 : 0) + 4
            }
            if staves.count > 1 {
                context.setFillColor(ink)
                let lineStart = left + 8
                context.fill(CGRect(x: lineStart - 4, y: firstTop, width: 2, height: lastTop + 4 * sp - firstTop))
                context.fill(CGRect(x: lineStart - 0.4, y: firstTop, width: 0.8, height: lastTop + 4 * sp - firstTop))
            }
            if options.showTranslation {
                let translations = song.phrases.filter { phrase in
                    guard let range = phrase.timeRange else { return false }
                    return range.start.doubleValue >= start - 1e-9 && range.start < system.measures.last!.range.end
                }.map(\.translation.value).filter { !$0.isEmpty }
                if !translations.isEmpty {
                    text(translations.joined(separator: "　／　"), font: Self.lyricFont, size: 7.5, x: musicLeft, baseline: staffY + 8, color: muted, in: context)
                }
            }
            _ = systemIndex
            y += system.height
        }
        let footer = "\(page + 1) / \(pageCount)"
        let width = StaffPainter.textWidth(footer, font: Self.lyricFont, size: 8)
        text(footer, font: Self.lyricFont, size: 8, x: (left + right - width) / 2, baseline: options.pageSize.height - options.margin + 14, color: muted, in: context)
    }

    /// Real (selectable) text in a y-down context.
    private func text(_ string: String, font: String, size: Double, x: Double, baseline: Double, color: CGColor, in context: CGContext) {
        guard !string.isEmpty else { return }
        let ctFont = CTFontCreateWithName(font as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): ctFont,
                                                         .init(kCTForegroundColorAttributeName as String): color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
