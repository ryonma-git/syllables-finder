import SwiftUI
import SongCore
import SongNotation

/// One row of measures engraved as a score: a staff per part with the lyrics beneath it.
/// x stays proportional to beats so the playhead and practice ranges match the piano roll.
struct ScoreRow: View {
    let song: SongDocument
    let measures: [MeasureSlice]
    let scale: Double
    @ObservedObject var session: WorkspaceSession
    let onMeasureTap: (MeasureSlice) -> Void
    let seek: (Double) -> Void
    @State private var layout: Layout?

    static let lyricFont = "HiraginoSans-W3"
    static func space(scale: Double) -> Double { min(15, max(9.5, scale * 0.2)) }
    static func leftMargin(song: SongDocument, scale: Double) -> Double {
        10 + StaffEngraving.headerWidth(space: space(scale: scale), meter: song.music.meters.first)
    }

    /// Nil when every part of these measures can be engraved; otherwise the reason to fall back.
    static func issue(song: SongDocument, measures: [MeasureSlice]) -> String? {
        for staff in ScoreStaff.all(in: song) {
            if let issue = NotationProjection(song: song, measures: measures, including: staff.include).issue {
                return song.music.parts.count > 1 ? "\(staff.name): \(issue)" : issue
            }
        }
        return nil
    }

    private var sp: Double { Self.space(scale: scale) }
    private var left: Double { Self.leftMargin(song: song, scale: scale) }
    private var start: Double { measures.first?.range.start.doubleValue ?? 0 }
    private var end: Double { measures.last?.range.end.doubleValue ?? start }
    private var width: Double { left + (end - start) * scale + 16 }
    private func x(_ beat: Double) -> Double { left + (beat - start) * scale }
    private var lyricSize: Double { 14 * session.textScale }
    private var lyricLines: Double {
        lyricSize + 8 + (session.showReading ? 11 * session.textScale + 5 : 0) + (session.showIPA ? 10 * session.textScale + 5 : 0)
    }

    private struct Block {
        let staff: ScoreStaff
        let engraving: StaffEngraving
        let lyrics: [LyricItem]
        let lyricTop: Double
    }

    private struct Layout {
        let blocks: [Block]
        let height: Double
    }

    private func blocks() -> ([Block], Double) {
        var blocks: [Block] = []
        var y = 62.0
        let staves = ScoreStaff.all(in: song)
        let songEnd = MeasureProjection.songEnd(song).doubleValue
        let firstMeasure = measures.first.map { $0.range.start == .zero } ?? false
        let range = BeatRange(start: measures.first?.range.start ?? .zero, end: measures.last?.range.end ?? .zero)
        for (index, staff) in staves.enumerated() {
            let padding = staff.padding(song: song)
            let staffTop = y + padding.above * sp
            let projection = NotationProjection(song: song, measures: measures, including: staff.include)
            let engraving = StaffEngraving(pieces: projection.pieces, measures: measures, meters: song.music.meters, clef: staff.clef,
                                           space: sp, staffTop: staffTop, lineStart: 10, lineEnd: x(end),
                                           headerX: 10, headerMeter: firstMeasure ? song.music.meters.first : nil,
                                           songEnd: songEnd, x: x)
            let size = lyricSize
            let lyrics = LyricLayout.items(song: song, range: range, include: staff.include, headLeft: engraving.headLeft, x: x,
                                           noteEnd: { engraving.headRight[$0] },
                                           measure: { StaffPainter.textWidth($0, font: Self.lyricFont, size: size) })
            let lyricTop = staffTop + (4 + padding.below) * sp
            blocks.append(.init(staff: staff, engraving: engraving, lyrics: lyrics, lyricTop: lyricTop))
            y = lyricTop + lyricLines + (index == 0 ? 18 : 10) * session.textScale
        }
        return (blocks, y + 34)
    }

    var body: some View {
        Group {
            if let layout {
                content(blocks: layout.blocks, height: layout.height)
            } else {
                ProgressView().frame(width: width, height: 90).task {
                    let (blocks, height) = blocks()
                    layout = Layout(blocks: blocks, height: height)
                }
            }
        }
    }

    private func content(blocks: [Block], height: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            highlights(blocks)
            Canvas { context, _ in
                for block in blocks {
                    for shape in StaffPainter.shapes(for: block.engraving) {
                        let path = Path(shape.path)
                        switch shape.style {
                        case .fill: context.fill(path, with: .foreground)
                        case .evenOddFill: context.fill(path, with: .foreground, style: FillStyle(eoFill: true))
                        case .stroke(let width): context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                        }
                    }
                    let baseline = block.lyricTop + lyricSize
                    for item in block.lyrics {
                        if let hyphen = item.hyphen {
                            let mid = (hyphen.from + hyphen.to) / 2
                            let half = min(3.5, (hyphen.to - hyphen.from) / 2 - 0.5)
                            context.fill(Path(CGRect(x: mid - half, y: baseline - lyricSize * 0.35, width: 2 * half, height: 1.2)), with: .foreground)
                        }
                        if let extender = item.extender {
                            context.fill(Path(CGRect(x: extender.from, y: baseline + 1, width: extender.to - extender.from, height: 1.1)), with: .foreground)
                        }
                    }
                }
                if blocks.count > 1, let first = blocks.first, let last = blocks.last {
                    let top = first.engraving.staffTop, bottom = last.engraving.staffTop + 4 * sp
                    context.fill(Path(CGRect(x: 4, y: top, width: 2.5, height: bottom - top)), with: .foreground)
                    context.fill(Path(CGRect(x: 10, y: top, width: 1, height: bottom - top)), with: .foreground)
                }
            }.foregroundStyle(Color.primary).allowsHitTesting(false)
            measureHeader
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if blocks.count > 1 {
                    Text(block.staff.abbreviation).font(.caption2.weight(.semibold)).foregroundStyle(.teal)
                        .offset(x: 14, y: block.engraving.staffTop - 2.9 * sp)
                        .accessibilityLabel("声部 \(block.staff.name)")
                }
                noteButtons(block)
                lyricButtons(block, showMeanings: index == 0)
            }
            if start <= session.position && session.position <= end {
                Rectangle().fill(Color.teal).frame(width: 2, height: height - 25)
                    .offset(x: x(session.position), y: 22).allowsHitTesting(false)
            }
            footer(height: height)
        }.frame(width: width, height: height)
    }

    private func highlights(_ blocks: [Block]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ForEach(block.engraving.hits.filter { $0.eventID == session.eventID }, id: \.x) { hit in
                    RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(0.28))
                        .frame(width: hit.width, height: hit.height).offset(x: hit.x, y: hit.y)
                }
                if let selected = session.syllableID {
                    ForEach(block.lyrics.filter { $0.syllableIDs.contains(selected) }) { item in
                        let ids = Set(song.alignments.filter { $0.languageTargets.contains(.init(.syllable, selected)) }
                            .flatMap(\.musicTargets).compactMap { target -> UUID? in if case .event(let id, _) = target { id } else { nil } })
                        ForEach(block.engraving.hits.filter { ids.contains($0.eventID) }, id: \.x) { hit in
                            RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(0.16))
                                .frame(width: hit.width, height: hit.height).offset(x: hit.x, y: hit.y)
                        }
                        RoundedRectangle(cornerRadius: 4).fill(Color.teal.opacity(0.22))
                            .frame(width: item.width + 6, height: lyricSize + 6).offset(x: item.x - 3, y: block.lyricTop - 1)
                    }
                }
            }
        }.allowsHitTesting(false)
    }

    private var measureHeader: some View {
        ZStack(alignment: .topLeading) {
            ForEach(measures) { measure in
                let from = x(measure.range.start.doubleValue)
                if let candidate = session.practiceCandidate ?? session.practiceRange,
                   candidate.start <= measure.range.start && measure.range.end <= candidate.end {
                    Rectangle().fill(Color.teal.opacity(session.practiceCandidate != nil ? 0.10 : 0.05))
                        .frame(width: measure.range.length * scale, height: 30).offset(x: from, y: 8)
                }
                Button(measure.inferred ? "\(measure.number)小節（推定）" : "\(measure.number)小節") { onMeasureTap(measure) }
                    .font(.caption.monospacedDigit()).buttonStyle(.plain)
                    .frame(width: max(50, measure.range.length * scale - 6), alignment: .leading)
                    .offset(x: from + 4, y: 12)
                    .accessibilityHint("Shiftキーで範囲を拡張")
            }
            HStack {
                Text("拍位置をクリックして移動").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.contentShape(Rectangle()).frame(width: max(0, width - left - 10), height: 18)
                .offset(x: left, y: 36)
                .onTapGesture { location in seek(start + max(0, min(end - start, location.x / scale))) }
        }
    }

    private func noteButtons(_ block: Block) -> some View {
        ForEach(Array(block.engraving.hits.enumerated()), id: \.offset) { _, hit in
            Button {
                session.eventID = hit.eventID; session.showNotes = true
                if let part = song.event(hit.eventID)?.partID { session.partID = part }
                if let phrase = song.phrases.first(where: { $0.musicalEventIDs.contains(hit.eventID) }) { session.phraseID = phrase.id }
            } label: {
                Color.clear.frame(width: hit.width, height: hit.height).contentShape(Rectangle())
            }.buttonStyle(.plain).offset(x: hit.x, y: hit.y)
                .help("\(Note(pitch: hit.pitch).name) · \(hit.duration.formatted())拍")
                .accessibilityLabel("音符 \(Note(pitch: hit.pitch).name)、\(hit.duration.formatted())拍")
        }
    }

    private func lyricButtons(_ block: Block, showMeanings: Bool) -> some View {
        ForEach(block.lyrics) { item in
            let syllables = item.syllableIDs.compactMap { song.syllable($0) }
            let reading = syllables.map { $0.reading.value.isEmpty ? "・" : $0.reading.value }.joined(separator: "‿")
            let ipa = syllables.map(\.ipa.value).filter { !$0.isEmpty }.joined(separator: "‿")
            Button {
                session.syllableID = item.syllableIDs[0]; session.wordID = syllables.first?.parentWordID
                session.showInspector = true
                if let part = block.staff.partID { session.partID = part }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.text).font(.custom(Self.lyricFont, size: lyricSize * item.fontScale)).fixedSize()
                        .frame(height: lyricSize, alignment: .bottom)
                    // Missing values stay blank under the staff (the tooltip and VoiceOver still say so);
                    // a placeholder per syllable would overlap on fast notes.
                    if session.showReading {
                        Text(syllables.allSatisfy { $0.reading.value.isEmpty } ? " " : reading)
                            .font(.system(size: 11 * session.textScale * max(0.75, item.fontScale))).foregroundStyle(.secondary).fixedSize()
                    }
                    if session.showIPA {
                        Text(ipa.isEmpty ? " " : "/\(ipa)/").font(.system(size: 10 * session.textScale * max(0.75, item.fontScale)))
                            .foregroundStyle(.secondary).fixedSize()
                    }
                }
            }.buttonStyle(.plain).offset(x: item.x, y: block.lyricTop)
                .accessibilityLabel("音節 \(item.text)、読み \(syllables.allSatisfy { $0.reading.value.isEmpty } ? "未設定" : reading)")
                .help(syllables.map { "\($0.text.value) · \($0.reading.value.isEmpty ? "読み未設定" : $0.reading.value)" }.joined(separator: " ／ "))
        }
    }

    private func footer(height: Double) -> some View {
        let translations = song.phrases.filter { phrase in
            guard let range = phrase.timeRange else { return false }
            return range.start.doubleValue < end && start < range.end.doubleValue
        }.map(\.translation.value).filter { !$0.isEmpty }
        return Text(translations.isEmpty ? "楽譜 · 音符・歌詞を選ぶと詳細を確認できます" : translations.joined(separator: " ／ "))
            .font(.system(size: 12 * session.textScale)).foregroundStyle(.secondary)
            .lineLimit(1).help(translations.joined(separator: " ／ "))
            .frame(width: max(0, width - left - 12), alignment: .leading)
            .offset(x: left + 4, y: height - 28)
    }
}

/// A staff to draw: one per part. Documents always have parts from schemaVersion 2; an empty
/// part list (a document without notes) still shows one empty treble staff.
struct ScoreStaff {
    let partID: UUID?
    let name: String
    let abbreviation: String
    let clef: Clef
    let include: (MusicalEvent) -> Bool

    static func all(in song: SongDocument) -> [ScoreStaff] {
        if song.music.parts.isEmpty {
            return [.init(partID: nil, name: "旋律", abbreviation: "", clef: .treble, include: { _ in true })]
        }
        return song.music.parts.map { part in
            let id = part.id
            return .init(partID: id, name: part.name, abbreviation: part.abbreviation.isEmpty ? String(part.name.prefix(2)) : part.abbreviation,
                         clef: part.clef, include: { $0.partID == id })
        }
    }

    func padding(song: SongDocument) -> (above: Double, below: Double) {
        let positions = song.music.events.filter(include).compactMap { $0.note?.pitch }.map { StaffEngraving.position(pitch: $0, clef: clef) }
        return StaffEngraving.padding(positions: positions)
    }
}
