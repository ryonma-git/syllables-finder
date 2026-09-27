import Foundation

public struct StaffPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public enum NoteheadKind: Sendable, Equatable { case black, half, whole }
public enum AccidentalKind: Sendable, Equatable {
    case sharp, flat, natural
    init?(symbol: String) {
        switch symbol {
        case "♯", "#": self = .sharp
        case "♭", "b": self = .flat
        case "♮": self = .natural
        default: return nil
        }
    }
}
public enum RestKind: Sendable, Equatable { case whole, half, quarter, eighth, sixteenth }

/// Drawing primitives in points, y growing downward from the row origin.
public enum StaffMark: Sendable, Equatable {
    case line(StaffPoint, StaffPoint, width: Double)
    case notehead(StaffPoint, NoteheadKind)
    /// A beam between the two points on its centre line.
    case beam(StaffPoint, StaffPoint, thickness: Double)
    /// `origin` is the free end of the stem.
    case flag(StaffPoint, count: Int, stemUp: Bool)
    case accidental(StaffPoint, AccidentalKind)
    case dot(StaffPoint)
    case rest(StaffPoint, RestKind)
    case tie(StaffPoint, StaffPoint, below: Bool)
    /// Left edge of the clef; the vertical frame comes from the staff.
    case clef(Clef, x: Double)
    /// Full-size stacked digits inside the staff, or a small label above it for mid-row changes.
    case timeSignature(numerator: Int, denominator: Int, centerX: Double, small: Bool)
}

public struct StaffNoteHit: Sendable, Equatable {
    public let eventID: UUID
    public let pitch: Int
    public let duration: Double
    public let x: Double, y: Double, width: Double, height: Double
}

/// Engraves one staff for one row of measures. All sizes derive from the staff space so that
/// noteheads sit exactly on lines and in spaces; x positions stay proportional to beats (ADR010).
public struct StaffEngraving: Sendable {
    public let space: Double
    public let staffTop: Double
    public let clef: Clef
    public private(set) var marks: [StaffMark] = []
    public private(set) var hits: [StaffNoteHit] = []
    /// Left edge of the first notehead drawn for each event in this row; lyrics start here.
    public private(set) var headLeft: [UUID: Double] = [:]
    /// Right edge of the last notehead drawn for each event in this row; extenders end here.
    public private(set) var headRight: [UUID: Double] = [:]
    public private(set) var minY: Double
    public private(set) var maxY: Double

    public static let stemLength = 3.5
    static let headWidth = 1.2, wholeWidth = 1.6
    static let stemWidth = 0.12, lineWidth = 0.1, beamThickness = 0.5, beamSpacing = 0.75

    /// Width in points needed left of the first measure for the clef and an optional time signature.
    public static func headerWidth(space: Double, meter: Meter?) -> Double {
        let digits = meter.map { max(String($0.numerator).count, String($0.denominator).count) } ?? 0
        return space * (0.5 + 2.8 + (meter == nil ? 0.6 : 0.9 + Double(digits) * 1.25 + 0.9))
    }

    /// Space (in staff spaces) needed above the top line and below the bottom line for these positions.
    public static func padding(positions: [Int]) -> (above: Double, below: Double) {
        let high = positions.max() ?? 8, low = positions.min() ?? 0
        return (max(2.2, Double(high - 8) / 2 + 1.2), max(2.2, Double(-low) / 2 + 1.2))
    }

    /// Staff position of an unspelled MIDI pitch (sharps for black keys except E♭, A♭, B♭).
    public static func position(pitch: Int, clef: Clef) -> Int {
        (pitch / 12) * 7 + [0, 0, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6][pitch % 12] - 7 - clef.bottomLineDiatonic
    }

    public static func position(of piece: StaffPiece, clef: Clef) -> Int? {
        piece.diatonic.map { $0 - clef.bottomLineDiatonic }
    }

    public func y(position: Int) -> Double { staffTop + Double(8 - position) * space / 2 }

    public init(pieces: [StaffPiece], measures: [MeasureSlice], meters: [Meter], clef: Clef,
                space: Double, staffTop: Double, lineStart: Double, lineEnd: Double,
                headerX: Double?, headerMeter: Meter?, songEnd: Double, x: (Double) -> Double) {
        self.space = space; self.staffTop = staffTop; self.clef = clef
        minY = staffTop; maxY = staffTop + 4 * space
        let sp = space
        for line in 0..<5 {
            let y = staffTop + Double(line) * sp
            add(.line(.init(lineStart, y), .init(lineEnd, y), width: max(0.8, Self.lineWidth * sp)))
        }
        if let headerX {
            add(.clef(clef, x: headerX + 0.5 * sp))
            extend(staffTop - 1.5 * sp); extend(staffTop + 5.7 * sp)
            if let headerMeter {
                let digits = max(String(headerMeter.numerator).count, String(headerMeter.denominator).count)
                add(.timeSignature(numerator: headerMeter.numerator, denominator: headerMeter.denominator,
                                   centerX: headerX + (0.5 + 2.8 + 0.9 + Double(digits) * 0.625) * sp, small: false))
            }
        }
        for (index, measure) in measures.enumerated() {
            let end = measure.range.end.doubleValue
            let barX = x(end)
            if abs(end - songEnd) < 1e-6 {
                let thick = 0.5 * sp
                add(.line(.init(barX - thick - 0.45 * sp, staffTop), .init(barX - thick - 0.45 * sp, staffTop + 4 * sp), width: 0.16 * sp))
                add(.line(.init(barX - thick / 2, staffTop), .init(barX - thick / 2, staffTop + 4 * sp), width: thick))
            } else {
                add(.line(.init(barX, staffTop), .init(barX, staffTop + 4 * sp), width: max(1, 0.16 * sp)))
            }
            let changesHere = meters.first { $0.onset == measure.range.start && $0.onset > .zero }
            let coveredByHeader = index == 0 && headerX != nil && headerMeter != nil
            if let meter = changesHere, !coveredByHeader {
                add(.timeSignature(numerator: meter.numerator, denominator: meter.denominator,
                                   centerX: x(measure.range.start.doubleValue) + 0.9 * sp, small: true))
                extend(staffTop - 2.6 * sp)
            }
        }
        engrave(pieces: pieces, measures: measures, meters: meters, lineStart: lineStart, lineEnd: lineEnd, x: x)
    }

    private mutating func add(_ mark: StaffMark) { marks.append(mark) }
    private mutating func extend(_ y: Double) { minY = min(minY, y); maxY = max(maxY, y) }

    private struct Head {
        let pieceIndex: Int
        let piece: StaffPiece
        let position: Int
        let centerX: Double
        let y: Double
        let width: Double
        var flags: Int {
            piece.duration < 0.5 - 1e-9 ? 2 : piece.duration < 1 - 1e-9 ? 1 : 0
        }
    }

    private static func isDotted(_ duration: Double) -> Bool {
        [3.0, 1.5, 0.75, 0.375].contains { abs($0 - duration) < 1e-9 }
    }

    private mutating func engrave(pieces: [StaffPiece], measures: [MeasureSlice], meters: [Meter],
                                  lineStart: Double, lineEnd: Double, x: (Double) -> Double) {
        let sp = space
        let middleY = staffTop + 2 * sp
        var heads: [Head] = []
        var wholeMeasureRests: Set<Int> = []
        for measure in measures {
            let from = measure.range.start.doubleValue, to = measure.range.end.doubleValue
            let inside = pieces.enumerated().filter { $0.element.start >= from - 1e-9 && $0.element.start < to - 1e-9 }
            if !inside.isEmpty && inside.allSatisfy({ $0.element.pitch == nil }) {
                inside.forEach { wholeMeasureRests.insert($0.offset) }
                let center = (x(from) + x(to)) / 2
                add(.rest(.init(center, staffTop + 1.25 * sp), .whole))
            }
        }
        for (index, piece) in pieces.enumerated() {
            if wholeMeasureRests.contains(index) { continue }
            guard piece.pitch != nil, let position = Self.position(of: piece, clef: clef) else {
                if piece.pitch == nil { engraveRest(piece, x: x) }
                continue
            }
            let accidental = piece.accidental.flatMap(AccidentalKind.init(symbol:))
            let kind: NoteheadKind = piece.duration >= 4 - 1e-9 ? .whole : piece.duration >= 2 - 1e-9 ? .half : .black
            let width = (kind == .whole ? Self.wholeWidth : Self.headWidth) * sp
            let left = x(piece.start) + (accidental == nil ? 0.5 : 1.75) * sp
            let y = self.y(position: position)
            let head = Head(pieceIndex: index, piece: piece, position: position, centerX: left + width / 2, y: y, width: width)
            heads.append(head)
            if let id = piece.eventID, headLeft[id] == nil { headLeft[id] = left }
            if let id = piece.eventID { headRight[id] = left + width }
            if let id = piece.eventID, let pitch = piece.pitch {
                hits.append(.init(eventID: id, pitch: pitch, duration: piece.duration,
                                  x: left - 0.2 * sp, y: y - 0.75 * sp, width: width + 0.4 * sp, height: 1.5 * sp))
            }
            // Ledger lines through every line position between the staff and the note.
            let ledgerHalf = width / 2 + 0.4 * sp
            if position <= -2 {
                for line in stride(from: -2, through: position, by: -2) {
                    let ly = self.y(position: line)
                    add(.line(.init(head.centerX - ledgerHalf, ly), .init(head.centerX + ledgerHalf, ly), width: max(0.8, 0.16 * sp)))
                }
            } else if position >= 10 {
                for line in stride(from: 10, through: position, by: 2) {
                    let ly = self.y(position: line)
                    add(.line(.init(head.centerX - ledgerHalf, ly), .init(head.centerX + ledgerHalf, ly), width: max(0.8, 0.16 * sp)))
                }
            }
            add(.notehead(.init(head.centerX, y), kind))
            extend(y - 0.6 * sp); extend(y + 0.6 * sp)
            if let accidental { add(.accidental(.init(left - 0.25 * sp - 0.45 * sp, y), accidental)) }
            if Self.isDotted(piece.duration) {
                let dotY = position % 2 == 0 ? self.y(position: position + 1) : y
                add(.dot(.init(left + width + 0.5 * sp, dotY)))
            }
        }
        engraveStems(heads, measures: measures, meters: meters, middleY: middleY)
        engraveTies(heads, lineStart: lineStart, lineEnd: lineEnd)
    }

    private mutating func engraveRest(_ piece: StaffPiece, x: (Double) -> Double) {
        let sp = space
        let kind: RestKind = piece.duration >= 4 - 1e-9 ? .whole : piece.duration >= 2 - 1e-9 ? .half
            : piece.duration >= 1 - 1e-9 ? .quarter : piece.duration >= 0.5 - 1e-9 ? .eighth : .sixteenth
        let centerX = x(piece.start) + 1.1 * sp
        let y: Double
        switch kind {
        case .whole: y = staffTop + 1.25 * sp   // hangs from the fourth line
        case .half: y = staffTop + 1.75 * sp    // sits on the middle line
        default: y = staffTop + 2 * sp
        }
        add(.rest(.init(centerX, y), kind))
        if Self.isDotted(piece.duration) { add(.dot(.init(centerX + 0.9 * sp, staffTop + 1.5 * sp))) }
    }

    private static func beamGroupLength(meter: Meter?) -> Double {
        guard let meter else { return 1 }
        if meter.denominator == 8 && meter.numerator % 3 == 0 { return 1.5 }
        if meter.denominator >= 8 { return 4 / Double(meter.denominator) * 2 }
        return 1
    }

    private mutating func engraveStems(_ heads: [Head], measures: [MeasureSlice], meters: [Meter], middleY: Double) {
        let sp = space
        var groups: [[Head]] = []
        var current: [Head] = []
        func groupKey(_ head: Head) -> (Int, Int)? {
            guard head.flags > 0,
                  let measureIndex = measures.firstIndex(where: {
                      $0.range.start.doubleValue <= head.piece.start + 1e-9 && head.piece.start < $0.range.end.doubleValue - 1e-9
                  }) else { return nil }
            let start = measures[measureIndex].range.start
            let meter = meters.last { $0.onset <= start }
            let length = Self.beamGroupLength(meter: meter)
            return (measureIndex, Int(((head.piece.start - start.doubleValue) + 1e-9) / length))
        }
        for head in heads {
            if let last = current.last, let a = groupKey(last), let b = groupKey(head),
               a == b, head.pieceIndex == last.pieceIndex + 1 {
                current.append(head)
            } else {
                if !current.isEmpty { groups.append(current) }
                current = [head]
            }
        }
        if !current.isEmpty { groups.append(current) }

        for group in groups {
            if group.count >= 2, group.allSatisfy({ $0.flags > 0 }) {
                engraveBeamedGroup(group, middleY: middleY)
                continue
            }
            for head in group where head.piece.duration < 4 - 1e-9 {
                let up = head.position < 4
                let stemX = up ? head.centerX + head.width / 2 - Self.stemWidth * sp / 2 : head.centerX - head.width / 2 + Self.stemWidth * sp / 2
                var end = up ? head.y - Self.stemLength * sp : head.y + Self.stemLength * sp
                if head.flags == 2 { end += up ? -0.5 * sp : 0.5 * sp }
                if up && end > middleY { end = middleY }
                if !up && end < middleY { end = middleY }
                add(.line(.init(stemX, head.y + (up ? -0.15 : 0.15) * sp), .init(stemX, end), width: Self.stemWidth * sp))
                extend(end)
                if head.flags > 0 {
                    add(.flag(.init(stemX, end), count: head.flags, stemUp: up))
                    extend(end + (up ? 3 : -3) * sp)
                }
            }
        }
    }

    private mutating func engraveBeamedGroup(_ group: [Head], middleY: Double) {
        let sp = space
        let farthest = group.max { abs($0.position - 4) < abs($1.position - 4) }!
        let up = farthest.position < 4
        let sign: Double = up ? -1 : 1
        let stemXs = group.map { up ? $0.centerX + $0.width / 2 - Self.stemWidth * sp / 2 : $0.centerX - $0.width / 2 + Self.stemWidth * sp / 2 }
        let first = group.first!, last = group.last!
        let x0 = stemXs.first!, x1 = stemXs.last!
        let levels = group.contains { $0.flags == 2 } ? 2 : 1
        var y0 = first.y + sign * Self.stemLength * sp
        var y1 = last.y + sign * Self.stemLength * sp
        let rise = max(-1 * sp, min(1 * sp, y1 - y0))
        y1 = y0 + rise
        func beamY(_ x: Double) -> Double { x1 == x0 ? y0 : y0 + (y1 - y0) * (x - x0) / (x1 - x0) }
        let minimum = (2.8 + Double(levels - 1) * Self.beamSpacing) * sp
        var shift = 0.0
        for (index, head) in group.enumerated() {
            let gap = (head.y - beamY(stemXs[index])) * -sign // positive when the beam is on the stem side
            shift = max(shift, minimum - gap)
        }
        y0 += sign * shift; y1 += sign * shift
        // Beams on the far side of the middle line are pulled back to reach it.
        if up && min(y0, y1) > middleY { let d = min(y0, y1) - middleY; y0 -= d; y1 -= d }
        if !up && max(y0, y1) < middleY { let d = middleY - max(y0, y1); y0 += d; y1 += d }
        let half = Self.stemWidth * sp / 2
        let thickness = Self.beamThickness * sp
        let inward = -sign // from the outer edge toward the noteheads
        for (index, head) in group.enumerated() {
            add(.line(.init(stemXs[index], head.y + sign * 0.15 * sp), .init(stemXs[index], beamY(stemXs[index])),
                      width: Self.stemWidth * sp))
        }
        func beam(level: Int, from a: Double, to b: Double) {
            let offset = inward * (thickness / 2 + Double(level) * Self.beamSpacing * sp)
            add(.beam(.init(a, beamY(a) + offset), .init(b, beamY(b) + offset), thickness: thickness))
        }
        beam(level: 0, from: x0 - half, to: x1 + half)
        if levels == 2 {
            var index = 0
            while index < group.count {
                guard group[index].flags == 2 else { index += 1; continue }
                var end = index
                while end + 1 < group.count && group[end + 1].flags == 2 { end += 1 }
                if end > index {
                    beam(level: 1, from: stemXs[index] - half, to: stemXs[end] + half)
                } else {
                    let towardPrevious = index > 0
                    let hook = min(1.1 * sp, abs((towardPrevious ? stemXs[index] - stemXs[index - 1] : stemXs[index + 1] - stemXs[index])) * 0.6)
                    beam(level: 1, from: towardPrevious ? stemXs[index] - hook : stemXs[index] - half,
                         to: towardPrevious ? stemXs[index] + half : stemXs[index] + hook)
                }
                index = end + 1
            }
        }
        extend(y0); extend(y1)
    }

    private mutating func engraveTies(_ heads: [Head], lineStart: Double, lineEnd: Double) {
        let sp = space
        for (index, head) in heads.enumerated() {
            let below = head.position >= 4 ? false : true
            let offset = (below ? 0.55 : -0.55) * sp
            if head.piece.tiedTo {
                let next = heads.dropFirst(index + 1).first { $0.piece.tiedFrom && $0.piece.pitch == head.piece.pitch }
                let endX = next.map { $0.centerX - $0.width / 2 - 0.1 * sp } ?? lineEnd - 0.2 * sp
                add(.tie(.init(head.centerX + head.width / 2 + 0.1 * sp, head.y + offset), .init(endX, head.y + offset), below: below))
                extend(head.y + offset + (below ? 0.7 : -0.7) * sp)
            }
            let hasStartInRow = heads.prefix(index).contains { $0.piece.tiedTo && $0.piece.pitch == head.piece.pitch }
            if head.piece.tiedFrom && !hasStartInRow {
                add(.tie(.init(lineStart + 0.2 * sp, head.y + offset), .init(head.centerX - head.width / 2 - 0.1 * sp, head.y + offset), below: below))
            }
        }
    }
}
