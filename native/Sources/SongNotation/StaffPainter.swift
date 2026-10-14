import CoreGraphics
import CoreText
import Foundation
import SongCore

/// A filled or stroked path in the engraving's y-down point space.
public struct StaffShape: @unchecked Sendable {
    public enum Style: Sendable, Equatable { case fill, evenOddFill, stroke(width: Double) }
    public let path: CGPath
    public let style: Style
}

/// Converts engraved marks into vector shapes. Glyphs come from font outlines fitted to
/// staff-space frames, so no text baseline or font metric decides a musical position.
public enum StaffPainter {
    public static func shapes(for engraving: StaffEngraving) -> [StaffShape] {
        let sp = engraving.space
        let top = engraving.staffTop
        var result: [StaffShape] = []
        func fill(_ path: CGPath) { result.append(.init(path: path, style: .fill)) }
        func stroke(_ path: CGPath, _ width: Double) { result.append(.init(path: path, style: .stroke(width: width))) }

        for mark in engraving.marks {
            switch mark {
            case .line(let a, let b, let width):
                // Lines are filled rectangles so that butt ends are exact at any scale.
                let path = CGMutablePath()
                if abs(a.x - b.x) < abs(a.y - b.y) {
                    path.addRect(CGRect(x: a.x - width / 2, y: min(a.y, b.y), width: width, height: abs(b.y - a.y)))
                } else {
                    path.addRect(CGRect(x: min(a.x, b.x), y: a.y - width / 2, width: abs(b.x - a.x), height: width))
                }
                fill(path)
            case .notehead(let c, let kind):
                result.append(.init(path: notehead(center: c, kind: kind, sp: sp), style: kind == .black ? .fill : .evenOddFill))
            case .beam(let a, let b, let thickness):
                let path = CGMutablePath()
                path.move(to: CGPoint(x: a.x, y: a.y - thickness / 2))
                path.addLine(to: CGPoint(x: b.x, y: b.y - thickness / 2))
                path.addLine(to: CGPoint(x: b.x, y: b.y + thickness / 2))
                path.addLine(to: CGPoint(x: a.x, y: a.y + thickness / 2))
                path.closeSubpath()
                fill(path)
            case .flag(let origin, let count, let stemUp):
                for index in 0..<count {
                    let shift = Double(index) * 0.8 * sp * (stemUp ? 1 : -1)
                    fill(flag(at: StaffPoint(origin.x, origin.y + shift), up: stemUp, sp: sp))
                }
            case .accidental(let c, let kind):
                result.append(contentsOf: accidental(center: c, kind: kind, sp: sp))
            case .dot(let c):
                fill(CGPath(ellipseIn: CGRect(x: c.x - 0.2 * sp, y: c.y - 0.2 * sp, width: 0.4 * sp, height: 0.4 * sp), transform: nil))
            case .rest(let c, let kind):
                result.append(contentsOf: rest(center: c, kind: kind, sp: sp))
            case .tie(let a, let b, let below):
                fill(tie(from: a, to: b, below: below, sp: sp))
            case .clef(let clef, let x):
                if let path = clefPath(clef, x: x, staffTop: top, sp: sp) { fill(path) }
            case .timeSignature(let numerator, let denominator, let centerX, let small):
                if small {
                    let height = 1.05 * sp
                    if let n = digitsPath(String(numerator), centerX: centerX, top: top - 2.5 * sp, height: height) { fill(n) }
                    if let d = digitsPath(String(denominator), centerX: centerX, top: top - 1.35 * sp, height: height) { fill(d) }
                } else {
                    let height = 1.9 * sp
                    if let n = digitsPath(String(numerator), centerX: centerX, top: top + 0.05 * sp, height: height) { fill(n) }
                    if let d = digitsPath(String(denominator), centerX: centerX, top: top + 2.05 * sp, height: height) { fill(d) }
                }
            }
        }
        return result
    }

    /// Draws into a y-down context (flip PDF/bitmap contexts before calling).
    public static func draw(_ engraving: StaffEngraving, in context: CGContext, color: CGColor) {
        for shape in shapes(for: engraving) { draw(shape, in: context, color: color) }
    }

    public static func draw(_ shape: StaffShape, in context: CGContext, color: CGColor) {
        context.saveGState()
        context.addPath(shape.path)
        switch shape.style {
        case .fill: context.setFillColor(color); context.fillPath()
        case .evenOddFill: context.setFillColor(color); context.fillPath(using: .evenOdd)
        case .stroke(let width):
            context.setStrokeColor(color); context.setLineWidth(width)
            context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: Noteheads, flags, ties

    private static func ellipse(_ c: StaffPoint, rx: Double, ry: Double, angle: Double) -> CGPath {
        var transform = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
        return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &transform)
    }

    static func notehead(center c: StaffPoint, kind: NoteheadKind, sp: Double) -> CGPath {
        let tilt = -20 * Double.pi / 180
        switch kind {
        case .black:
            return ellipse(c, rx: 0.62 * sp, ry: 0.46 * sp, angle: tilt)
        case .half:
            let path = CGMutablePath()
            path.addPath(ellipse(c, rx: 0.62 * sp, ry: 0.46 * sp, angle: tilt))
            path.addPath(ellipse(c, rx: 0.5 * sp, ry: 0.2 * sp, angle: -35 * Double.pi / 180))
            return path
        case .whole:
            let path = CGMutablePath()
            path.addPath(ellipse(c, rx: 0.8 * sp, ry: 0.5 * sp, angle: 0))
            path.addPath(ellipse(c, rx: 0.36 * sp, ry: 0.3 * sp, angle: 50 * Double.pi / 180))
            return path
        }
    }

    static func flag(at o: StaffPoint, up: Bool, sp: Double) -> CGPath {
        let s: Double = up ? 1 : -1
        let path = CGMutablePath()
        path.move(to: CGPoint(x: o.x, y: o.y))
        path.addCurve(to: CGPoint(x: o.x + 0.9 * sp, y: o.y + s * 2.7 * sp),
                      control1: CGPoint(x: o.x + 0.1 * sp, y: o.y + s * 1.0 * sp),
                      control2: CGPoint(x: o.x + 1.35 * sp, y: o.y + s * 1.4 * sp))
        path.addCurve(to: CGPoint(x: o.x, y: o.y + s * 0.95 * sp),
                      control1: CGPoint(x: o.x + 1.0 * sp, y: o.y + s * 1.85 * sp),
                      control2: CGPoint(x: o.x + 0.3 * sp, y: o.y + s * 1.35 * sp))
        path.closeSubpath()
        return path
    }

    static func tie(from a: StaffPoint, to b: StaffPoint, below: Bool, sp: Double) -> CGPath {
        let s: Double = below ? 1 : -1
        let length = max(0, b.x - a.x)
        let depth = min(0.75 * sp, 0.25 * sp + length * 0.08)
        let mid = (a.x + b.x) / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: a.x, y: a.y))
        path.addQuadCurve(to: CGPoint(x: b.x, y: b.y), control: CGPoint(x: mid, y: (a.y + b.y) / 2 + s * depth * 2))
        path.addQuadCurve(to: CGPoint(x: a.x, y: a.y), control: CGPoint(x: mid, y: (a.y + b.y) / 2 + s * (depth * 2 - 0.3 * sp)))
        path.closeSubpath()
        return path
    }

    // MARK: Accidentals and rests (drawn geometrically, no font dependence)

    private static func bar(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, thickness: Double) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0, y: y0 - thickness / 2))
        path.addLine(to: CGPoint(x: x1, y: y1 - thickness / 2))
        path.addLine(to: CGPoint(x: x1, y: y1 + thickness / 2))
        path.addLine(to: CGPoint(x: x0, y: y0 + thickness / 2))
        path.closeSubpath()
        return path
    }

    private static func vertical(_ x: Double, _ y0: Double, _ y1: Double, width: Double) -> CGPath {
        CGPath(rect: CGRect(x: x - width / 2, y: y0, width: width, height: y1 - y0), transform: nil)
    }

    static func accidental(center c: StaffPoint, kind: AccidentalKind, sp: Double) -> [StaffShape] {
        let thin = 0.12 * sp, thick = 0.3 * sp
        switch kind {
        case .sharp:
            return [
                .init(path: vertical(c.x - 0.22 * sp, c.y - 1.2 * sp, c.y + 1.4 * sp, width: thin), style: .fill),
                .init(path: vertical(c.x + 0.22 * sp, c.y - 1.4 * sp, c.y + 1.2 * sp, width: thin), style: .fill),
                .init(path: bar(c.x - 0.5 * sp, c.y - 0.3 * sp, c.x + 0.5 * sp, c.y - 0.6 * sp, thickness: thick), style: .fill),
                .init(path: bar(c.x - 0.5 * sp, c.y + 0.6 * sp, c.x + 0.5 * sp, c.y + 0.3 * sp, thickness: thick), style: .fill)
            ]
        case .natural:
            return [
                .init(path: vertical(c.x - 0.28 * sp, c.y - 1.35 * sp, c.y + 0.6 * sp, width: thin), style: .fill),
                .init(path: vertical(c.x + 0.28 * sp, c.y - 0.6 * sp, c.y + 1.35 * sp, width: thin), style: .fill),
                .init(path: bar(c.x - 0.28 * sp, c.y - 0.3 * sp, c.x + 0.28 * sp, c.y - 0.52 * sp, thickness: thick), style: .fill),
                .init(path: bar(c.x - 0.28 * sp, c.y + 0.52 * sp, c.x + 0.28 * sp, c.y + 0.3 * sp, thickness: thick), style: .fill)
            ]
        case .flat:
            let stemX = c.x - 0.3 * sp
            let bowl = CGMutablePath()
            bowl.move(to: CGPoint(x: stemX, y: c.y - 0.1 * sp))
            bowl.addCurve(to: CGPoint(x: stemX, y: c.y + 0.6 * sp),
                          control1: CGPoint(x: stemX + 0.9 * sp, y: c.y - 0.75 * sp),
                          control2: CGPoint(x: stemX + 1.05 * sp, y: c.y + 0.05 * sp))
            bowl.addLine(to: CGPoint(x: stemX, y: c.y + 0.42 * sp))
            bowl.addCurve(to: CGPoint(x: stemX, y: c.y + 0.12 * sp),
                          control1: CGPoint(x: stemX + 0.65 * sp, y: c.y + 0.05 * sp),
                          control2: CGPoint(x: stemX + 0.5 * sp, y: c.y - 0.4 * sp))
            bowl.closeSubpath()
            return [.init(path: vertical(stemX, c.y - 1.8 * sp, c.y + 0.6 * sp, width: thin), style: .fill),
                    .init(path: bowl, style: .fill)]
        }
    }

    static func rest(center c: StaffPoint, kind: RestKind, sp: Double) -> [StaffShape] {
        switch kind {
        case .whole, .half:
            return [.init(path: CGPath(rect: CGRect(x: c.x - 0.6 * sp, y: c.y - 0.25 * sp, width: 1.2 * sp, height: 0.5 * sp), transform: nil), style: .fill)]
        case .quarter:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: c.x - 0.15 * sp, y: c.y - 1.45 * sp))
            path.addLine(to: CGPoint(x: c.x + 0.42 * sp, y: c.y - 0.62 * sp))
            path.addLine(to: CGPoint(x: c.x - 0.12 * sp, y: c.y - 0.02 * sp))
            path.addLine(to: CGPoint(x: c.x + 0.4 * sp, y: c.y + 0.62 * sp))
            path.addQuadCurve(to: CGPoint(x: c.x + 0.08 * sp, y: c.y + 1.45 * sp), control: CGPoint(x: c.x - 0.6 * sp, y: c.y + 0.5 * sp))
            let thick = CGMutablePath()
            thick.move(to: CGPoint(x: c.x + 0.36 * sp, y: c.y - 0.6 * sp))
            thick.addLine(to: CGPoint(x: c.x - 0.08 * sp, y: c.y - 0.05 * sp))
            return [.init(path: path, style: .stroke(width: 0.2 * sp)), .init(path: thick, style: .stroke(width: 0.42 * sp))]
        case .eighth, .sixteenth:
            var shapes: [StaffShape] = []
            let tops = kind == .eighth ? [0.0] : [0.0, 1.0]
            let stemTop = CGPoint(x: c.x + 0.5 * sp, y: c.y - 0.75 * sp)
            let stemBottom = CGPoint(x: c.x + (kind == .eighth ? 0.05 : -0.15) * sp, y: c.y + (kind == .eighth ? 1.1 : 2.1) * sp)
            let stem = CGMutablePath(); stem.move(to: stemTop); stem.addLine(to: stemBottom)
            shapes.append(.init(path: stem, style: .stroke(width: 0.14 * sp)))
            for offset in tops {
                let t = offset * sp
                let along = offset / (kind == .eighth ? 1 : 2.85)
                let join = CGPoint(x: stemTop.x + (stemBottom.x - stemTop.x) * along, y: stemTop.y + t)
                let dot = CGPoint(x: c.x - 0.3 * sp - offset * 0.2 * sp, y: c.y - 0.5 * sp + t)
                shapes.append(.init(path: CGPath(ellipseIn: CGRect(x: dot.x - 0.24 * sp, y: dot.y - 0.24 * sp, width: 0.48 * sp, height: 0.48 * sp), transform: nil), style: .fill))
                let arm = CGMutablePath()
                arm.move(to: CGPoint(x: dot.x, y: dot.y + 0.1 * sp))
                arm.addQuadCurve(to: join, control: CGPoint(x: (dot.x + join.x) / 2, y: dot.y + 0.45 * sp))
                shapes.append(.init(path: arm, style: .stroke(width: 0.14 * sp)))
            }
            return shapes
        }
    }

    // MARK: Font glyph outlines fitted to staff frames

    private static func glyphPath(_ text: String, font name: String) -> (CGPath, CGRect)? {
        let font = CTFontCreateWithName(name as CFString, 100, nil)
        let attributed = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                path.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
            }
        }
        let box = path.boundingBoxOfPath
        guard !path.isEmpty, box.height > 0 else { return nil }
        return (path, box)
    }

    /// Scales a y-up glyph outline so its box spans `top...top+height` in the y-down space.
    private static func fitted(_ glyph: (CGPath, CGRect), left: Double, top: Double, height: Double) -> CGPath {
        let (path, box) = glyph
        let scale = height / box.height
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                          tx: left - box.minX * scale, ty: top + height + box.minY * scale)
        var t = transform
        return path.copy(using: &t) ?? path
    }

    static func clefPath(_ clef: Clef, x: Double, staffTop: Double, sp: Double) -> CGPath? {
        switch clef {
        case .treble, .treble8vb:
            // G clef frame: its curl centres on the second line (y = 3 sp).
            guard let glyph = glyphPath("\u{1D11E}", font: "AppleSymbols") else { return nil }
            let path = CGMutablePath()
            path.addPath(fitted(glyph, left: x, top: staffTop - 1.45 * sp, height: 7.1 * sp))
            if clef == .treble8vb, let eight = glyphPath("8", font: "Times-Bold") {
                let width = glyph.1.width * 7.1 * sp / glyph.1.height
                let digitHeight = 1.0 * sp
                let digitWidth = eight.1.width * digitHeight / eight.1.height
                path.addPath(fitted(eight, left: x + width / 2 - digitWidth / 2, top: staffTop + 5.75 * sp, height: digitHeight))
            }
            return path
        case .bass:
            // F clef frame: its head hangs from the fourth line (y = 1 sp), dots around it.
            guard let glyph = glyphPath("\u{1D122}", font: "AppleSymbols") else { return nil }
            return fitted(glyph, left: x, top: staffTop - 0.05 * sp, height: 3.25 * sp)
        }
    }

    /// Text as an outline with its baseline at `baseline`, for y-down contexts.
    public static func textPath(_ text: String, font: String, size: Double, x: Double, baseline: Double) -> (path: CGPath, width: Double)? {
        guard let (path, _) = glyphPath(text, font: font) else { return nil }
        let ctFont = CTFontCreateWithName(font as CFString, 100, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): ctFont]))
        let advance = CTLineGetTypographicBounds(line, nil, nil, nil) * size / 100
        var transform = CGAffineTransform(a: size / 100, b: 0, c: 0, d: -size / 100, tx: x, ty: baseline)
        return (path.copy(using: &transform) ?? path, advance)
    }

    public static func textWidth(_ text: String, font: String, size: Double) -> Double {
        let ctFont = CTFontCreateWithName(font as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): ctFont]))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    static func digitsPath(_ digits: String, centerX: Double, top: Double, height: Double) -> CGPath? {
        guard let glyph = glyphPath(digits, font: "Times-Bold") else { return nil }
        let width = glyph.1.width * height / glyph.1.height
        return fitted(glyph, left: centerX - width / 2, top: top, height: height)
    }
}
