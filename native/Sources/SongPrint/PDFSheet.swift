import AppKit
import CoreGraphics
import Foundation

private extension PrintRGBColor {
    var nsColor: NSColor {
        NSColor(calibratedRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: 1)
    }
}

@MainActor
public enum PDFSheet {
    public static func render(_ sheet: PrintSheet) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw PrintError.creationFailed }
        var paper = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // ISO A4, points
        guard let context = CGContext(consumer: consumer, mediaBox: &paper, nil) else {
            throw PrintError.creationFailed
        }
        let painter = PDFPainter(context: context, sheet: sheet, pageSize: paper.size)
        do { try painter.render(sheet) }
        catch { context.closePDF(); throw error }
        // Closing writes the PDF trailer. Finish it before bridging NSMutableData to Data,
        // which may copy the buffer while evaluating the return expression.
        context.closePDF()
        return output as Data
    }
}

public enum PrintError: Error, LocalizedError {
    case creationFailed
    case archiveFailed
    case layoutFailed

    public var errorDescription: String? {
        switch self {
        case .creationFailed: "印刷用PDFを作成できませんでした。"
        case .archiveFailed: "Wordファイルを作成できませんでした。"
        case .layoutFailed: "文章をPDFの印刷可能範囲に配置できませんでした。文字や改行を確認してください。"
        }
    }
}

@MainActor
private final class PDFPainter {
    private let context: CGContext
    private let title: String
    private let order: ReadingOrder
    private let appearance: PrintAppearance
    private let pronunciationLabel: String?
    private let colorLegend: String
    private let size: CGSize
    private var accent: NSColor { appearance.accent.nsColor }
    private var nucleus: NSColor { appearance.vowelNucleus.nsColor }
    private let dark = NSColor(calibratedWhite: 0.14, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.39, alpha: 1)
    private let line = NSColor(calibratedWhite: 0.85, alpha: 1)
    private var margin: CGFloat { appearance.design == .compact ? 28 : appearance.design == .largePrint ? 40 : 34 }
    private var typeScale: CGFloat { appearance.design == .compact ? 0.91 : appearance.design == .largePrint ? 1.17 : 1 }
    private var phraseGap: CGFloat { appearance.design == .compact ? 3 : appearance.design == .largePrint ? 9 : 6 }
    private var rowGap: CGFloat { appearance.design == .compact ? 1 : appearance.design == .largePrint ? 3 : 2 }
    private func fontSize(_ base: CGFloat) -> CGFloat { base * typeScale }
    private var page = 0
    private var y: CGFloat = 0
    private var contentTop: CGFloat = 90
    private var priorGraphics: NSGraphicsContext?
    private var section = ""
    private var contentWidth: CGFloat { size.width - 2 * margin }
    private var footerTop: CGFloat { size.height - 42 }
    private var contentBottom: CGFloat { footerTop - 12 }
    private var pageCapacity: CGFloat { contentBottom - contentTop }
    private var wordGap: CGFloat { appearance.design == .compact ? 3 : appearance.design == .largePrint ? 5 : 4 }
    private var titleFont: NSFont { .systemFont(ofSize: fontSize(20), weight: .semibold) }
    // An unusually long title is printed in full once, as flowing content. Repeating it in
    // every page header would leave little (or no) room for the song itself.
    private var extendedTitle: Bool { textHeight(title, width: contentWidth, font: titleFont) > 90 }

    init(context: CGContext, sheet: PrintSheet, pageSize: CGSize) {
        self.context = context; self.title = sheet.title; self.size = pageSize
        self.order = sheet.order
        self.appearance = sheet.appearance
        self.pronunciationLabel = sheet.pronunciationLabel
        self.colorLegend = sheet.colorLegend
    }

    func render(_ sheet: PrintSheet) throws {
        startPage()
        defer { endPage() }
        if extendedTitle {
            try drawFlowingText(attributed(title, font: titleFont, color: dark), x: margin,
                            width: contentWidth)
            y += 10
        }
        if sheet.phrases.isEmpty {
            y += 24
            drawText("歌詞はまだありません。", x: margin, y: y, width: contentWidth,
                     font: .systemFont(ofSize: fontSize(13)), color: muted)
        } else {
            for (index, phrase) in sheet.phrases.enumerated() { try drawPhrase(phrase, index: index) }
        }
    }

    private func startPage() {
        page += 1
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        priorGraphics = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawText("SINGING WORKSPACE", x: margin, y: 17, width: contentWidth,
                 font: .systemFont(ofSize: 9, weight: .semibold), color: accent, tracking: 1.6)
        let titleHeight = drawText(extendedTitle ? "歌唱練習シート" : title,
                                   x: margin, y: 31, width: contentWidth, font: titleFont, color: dark)
        let legendY = max(62, 31 + titleHeight + 4)
        let legendHeight = drawText(order.legend + (pronunciationLabel.map { "　｜" + $0 } ?? ""),
                                    x: margin, y: legendY, width: contentWidth,
                                    font: .systemFont(ofSize: 9), color: muted)
        let ruleY = max(81, legendY + legendHeight + 4)
        fill(CGRect(x: margin, y: ruleY, width: contentWidth, height: 1), line)
        contentTop = ruleY + 9
        y = contentTop
    }

    private func endPage() {
        fill(CGRect(x: margin, y: footerTop, width: contentWidth, height: 1), line)
        drawText(colorLegend, x: margin, y: footerTop + 11,
                 width: contentWidth - 55, font: .systemFont(ofSize: 8.5), color: muted)
        drawText("\(page)", x: size.width - margin - 30, y: footerTop + 11, width: 30,
                 font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular), color: muted,
                 alignment: .right)
        NSGraphicsContext.current = priorGraphics
        context.restoreGState()
        context.endPDFPage()
    }

    @discardableResult
    private func ensure(_ height: CGFloat) -> Bool {
        guard y + height > contentBottom, y > contentTop else { return false }
        endPage(); startPage()
        return true
    }

    private func continuePage(phraseIndex: Int?) {
        endPage(); startPage()
        if let phraseIndex {
            y += drawText(String(format: "%02d（続き）", phraseIndex + 1), x: margin, y: y,
                          width: contentWidth, font: .systemFont(ofSize: fontSize(9), weight: .semibold),
                          color: accent) + 2
        }
    }

    private func drawPhrase(_ phrase: PrintPhrase, index: Int) throws {
        let rows = flow(phrase.words)
        let before = order.beforeTranslation
        let after = order.afterTranslation
        func blockHeight(_ elements: [ReadingElement]) -> CGFloat {
            guard !elements.isEmpty else { return 0 }
            return rows.reduce(0) { $0 + $1.height(for: elements) + rowGap }
        }
        let originalFont = NSFont.systemFont(ofSize: fontSize(11), weight: .medium)
        let originalHeight = phrase.original.isEmpty ? 0 :
            textHeight(phrase.original, width: contentWidth - 30, font: originalFont) + 4
        let translationHeight = phrase.translation.isEmpty ? 0 :
            textHeight(phrase.translation, width: contentWidth - 30, font: .systemFont(ofSize: fontSize(10))) + 3
        let sectionHeight: CGFloat = phrase.section == section ? 0 : 14
        let wholeHeight = originalHeight + blockHeight(before) + blockHeight(after)
            + CGFloat(translationHeight) + phraseGap + sectionHeight
        if wholeHeight <= pageCapacity && y + wholeHeight > contentBottom { endPage(); startPage() }
        let firstBlockHeight = before.isEmpty ? CGFloat(translationHeight)
            : (rows.first?.height(for: before) ?? 0)
        ensure(min(wholeHeight, sectionHeight + originalHeight + firstBlockHeight + 8))
        if section != phrase.section {
            section = phrase.section
            try drawFlowingText(attributed(section, font: .systemFont(ofSize: fontSize(10), weight: .bold), color: accent),
                            x: margin, width: contentWidth)
            y += 1
        }
        ensure(fontSize(11) + 5)
        drawText(String(format: "%02d", index + 1), x: margin, y: y + 1, width: 28,
                 font: .monospacedDigitSystemFont(ofSize: fontSize(10), weight: .semibold), color: accent)
        if !phrase.original.isEmpty {
            try drawFlowingText(attributed(phrase.original, font: originalFont, color: dark),
                            x: margin + 30, width: contentWidth - 30, phraseIndex: index)
            y += 4
        }
        try drawBlock(phrase, index: index, rows: rows, elements: before)
        if !phrase.translation.isEmpty {
            try drawFlowingText(attributed(phrase.translation, font: .systemFont(ofSize: fontSize(10)), color: dark),
                            x: margin + 30, width: contentWidth - 30, phraseIndex: index)
            y += 3
        }
        try drawBlock(phrase, index: index, rows: rows, elements: after)
        y += phraseGap
    }

    private func drawBlock(_ phrase: PrintPhrase, index: Int, rows: [WordRow],
                           elements: [ReadingElement]) throws {
        guard !elements.isEmpty else { return }
        for row in rows {
            if row.height(for: elements) + rowGap > pageCapacity - 18 {
                // Keep ordinary word rows together. For an oversized row, flow each selected
                // annotation layer across pages while retaining its columns and attributed colors.
                for element in elements {
                    let values = row.words.map { wordText($0, element: element) }
                    try drawFlowingColumns(values, x: margin + 30, widths: row.widths, phraseIndex: index)
                    y += 1
                }
                y += rowGap
                continue
            }
            if ensure(row.height(for: elements) + rowGap) {
                drawText("\(String(format: "%02d", index + 1))（続き）",
                         x: margin, y: y, width: contentWidth,
                         font: .systemFont(ofSize: fontSize(9), weight: .semibold), color: accent)
                y += 14
            }
            var x = margin + 30
            for (word, width) in zip(row.words, row.widths) {
                drawWord(word, x: x, y: y, width: width, row: row, elements: elements)
                x += width + wordGap
            }
            y += row.height(for: elements) + rowGap
        }
    }

    private struct WordRow {
        var words: [PrintWord]
        var widths: [CGFloat]
        var meaningHeight: CGFloat
        var lyricHeight: CGFloat
        var ipaHeight: CGFloat
        var readingHeight: CGFloat
        func height(for element: ReadingElement) -> CGFloat {
            switch element {
            case .original: lyricHeight
            case .reading: readingHeight
            case .ipa: ipaHeight
            case .meaning: meaningHeight
            case .translation: 0
            }
        }
        func height(for elements: [ReadingElement]) -> CGFloat {
            elements.reduce(CGFloat(1)) { $0 + height(for: $1) + 1 }
        }
    }

    private func flow(_ words: [PrintWord]) -> [WordRow] {
        var rows: [WordRow] = []
        var current: [PrintWord] = []
        var widths: [CGFloat] = []
        var used: CGFloat = 0
        func finish() {
            guard !current.isEmpty else { return }
            rows.append(WordRow(words: current, widths: widths,
                meaningHeight: zip(current, widths).map { textHeight($0.0.meaning.isEmpty ? "意味未設定" : $0.0.meaning,
                    width: $0.1, font: .systemFont(ofSize: fontSize(8.5))) }.max() ?? 0,
                lyricHeight: zip(current, widths).map { richHeight(segmented($0.0), width: $0.1) }.max() ?? 18,
                ipaHeight: zip(current, widths).map { textHeight($0.0.ipa.isEmpty ? "IPA未設定" : $0.0.ipa,
                    width: $0.1, font: .systemFont(ofSize: fontSize(8.5))) }.max() ?? 0,
                readingHeight: zip(current, widths).map { textHeight($0.0.reading.isEmpty ? "カタカナ未設定" : $0.0.reading,
                    width: $0.1, font: .systemFont(ofSize: fontSize(8.5))) }.max() ?? 0))
            current = []; widths = []; used = 0
        }
        for word in words {
            let lyric = segmented(word).size().width
            let annotation = [word.meaning, word.ipa, word.reading]
                .map { attributed($0, font: .systemFont(ofSize: fontSize(8.5)), color: muted).size().width }
                .max() ?? 0
            let width = min(170, max(24, lyric, annotation) + 2)
            if !current.isEmpty && used + wordGap + width > contentWidth - 30 { finish() }
            if !current.isEmpty { used += wordGap }
            current.append(word); widths.append(width); used += width
        }
        finish()
        return rows
    }

    private func drawWord(_ word: PrintWord, x: CGFloat, y: CGFloat, width: CGFloat,
                          row: WordRow, elements: [ReadingElement]) {
        var position = y
        for element in elements {
            switch element {
            case .original:
                segmented(word).draw(with: CGRect(x: x, y: position, width: width, height: row.lyricHeight),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
            case .reading:
                drawText(word.reading.isEmpty ? "カタカナ未設定" : word.reading,
                         x: x, y: position, width: width, font: .systemFont(ofSize: fontSize(8.5)), color: muted)
            case .ipa:
                drawText(word.ipa.isEmpty ? "IPA未設定" : word.ipa,
                         x: x, y: position, width: width, font: .systemFont(ofSize: fontSize(8.5)), color: dark)
            case .meaning:
                drawText(word.meaning.isEmpty ? "意味未設定" : word.meaning,
                         x: x, y: position, width: width, font: .systemFont(ofSize: fontSize(8.5)), color: muted)
            case .translation: break
            }
            position += row.height(for: element) + 1
        }
    }

    private func segmented(_ word: PrintWord) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let font = NSFont.systemFont(ofSize: fontSize(13), weight: .semibold)
        for fragment in word.displayFragments {
            result.append(NSAttributedString(string: fragment.text, attributes: [
                .font: font, .foregroundColor: fragment.isColored ? nucleus : dark
            ]))
        }
        return result
    }

    private func wordText(_ word: PrintWord, element: ReadingElement) -> NSAttributedString {
        switch element {
        case .original: segmented(word)
        case .reading: attributed(word.reading.isEmpty ? "カタカナ未設定" : word.reading,
                                  font: .systemFont(ofSize: fontSize(8.5)), color: muted)
        case .ipa: attributed(word.ipa.isEmpty ? "IPA未設定" : word.ipa,
                              font: .systemFont(ofSize: fontSize(8.5)), color: dark)
        case .meaning: attributed(word.meaning.isEmpty ? "意味未設定" : word.meaning,
                                  font: .systemFont(ofSize: fontSize(8.5)), color: muted)
        case .translation: NSAttributedString(string: "")
        }
    }

    /// TextKit supplies complete visual-line boundaries, including explicit newlines and
    /// composed characters. A page fragment always ends on one of those boundaries; no
    /// text is clipped and the remaining attributed substring is carried to the next page.
    private struct TextFlow {
        let value: NSAttributedString
        let width: CGFloat
        let lineEnds: [Int]
        var offset = 0
        var isEmpty: Bool { offset == value.length }

        init(_ value: NSAttributedString, width: CGFloat) {
            self.value = value; self.width = width
            let storage = NSTextStorage(attributedString: value)
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager); manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            var ends: [Int] = []
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, glyphs, _ in
                let end = NSMaxRange(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
                if end > (ends.last ?? 0) { ends.append(end) }
            }
            if value.length > (ends.last ?? 0) { ends.append(value.length) }
            lineEnds = ends
        }

        static func height(_ value: NSAttributedString, width: CGFloat) -> CGFloat {
            guard value.length > 0 else { return 0 }
            let font = value.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            return max((font?.pointSize ?? 0) + 3,
                       ceil(value.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
        }

        var remainingHeight: CGFloat {
            Self.height(value.attributedSubstring(from: NSRange(location: offset, length: value.length - offset)), width: width)
        }

        var nextLineHeight: CGFloat {
            guard let end = lineEnds.first(where: { $0 > offset }) else { return 0 }
            return Self.height(value.attributedSubstring(from: NSRange(location: offset, length: end - offset)), width: width)
        }

        mutating func take(height: CGFloat) -> NSAttributedString? {
            let ends = lineEnds.filter { $0 > offset }
            var low = 0, high = ends.count
            while low < high {
                let middle = (low + high) / 2
                let fragment = value.attributedSubstring(from: NSRange(location: offset, length: ends[middle] - offset))
                if Self.height(fragment, width: width) <= height { low = middle + 1 } else { high = middle }
            }
            guard low > 0 else { return nil }
            let end = ends[low - 1]
            let fragment = value.attributedSubstring(from: NSRange(location: offset, length: end - offset))
            offset = end
            return fragment
        }
    }

    private func drawFlowingText(_ value: NSAttributedString, x: CGFloat, width: CGFloat,
                                 phraseIndex: Int? = nil) throws {
        try drawFlowingColumns([value], x: x, widths: [width], phraseIndex: phraseIndex)
    }

    private func drawFlowingColumns(_ values: [NSAttributedString], x: CGFloat, widths: [CGFloat],
                                    phraseIndex: Int?) throws {
        var flows = zip(values, widths).map { TextFlow($0.0, width: $0.1) }
        let fullHeight = flows.map(\.remainingHeight).max() ?? 0
        if fullHeight <= pageCapacity - 18 && y + fullHeight > contentBottom {
            continuePage(phraseIndex: phraseIndex)
        }
        while flows.contains(where: { !$0.isEmpty }) {
            let firstLineHeight = flows.map(\.nextLineHeight).max() ?? 0
            if y + firstLineHeight > contentBottom { continuePage(phraseIndex: phraseIndex) }
            let available = contentBottom - y
            // Do not loop forever or silently discard text if font layout ever returns a
            // line that cannot fit even on a fresh page.
            guard firstLineHeight.isFinite, firstLineHeight <= available else { throw PrintError.layoutFailed }
            var columnX = x
            var height: CGFloat = 0
            for index in flows.indices {
                if let fragment = flows[index].take(height: available) {
                    let fragmentHeight = TextFlow.height(fragment, width: widths[index])
                    fragment.draw(with: CGRect(x: columnX, y: y, width: widths[index], height: fragmentHeight),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading])
                    height = max(height, fragmentHeight)
                }
                columnX += widths[index] + wordGap
            }
            guard height > 0 else { throw PrintError.layoutFailed }
            y += height
            if flows.contains(where: { !$0.isEmpty }) { continuePage(phraseIndex: phraseIndex) }
        }
    }

    private func richHeight(_ value: NSAttributedString, width: CGFloat) -> CGFloat {
        max(18, ceil(value.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
    }

    private func fill(_ rect: CGRect, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let value = attributed(text, font: font, color: dark)
        return max(font.pointSize + 3, ceil(value.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                              options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
    }

    @discardableResult
    private func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: NSFont,
                          color: NSColor, tracking: CGFloat = 0,
                          alignment: NSTextAlignment = .left) -> CGFloat {
        let height = textHeight(text, width: width, font: font)
        guard height > 0 else { return 0 }
        let value = attributed(text, font: font, color: color, tracking: tracking, alignment: alignment)
        value.draw(with: CGRect(x: x, y: y, width: width, height: height),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
        return height
    }

    private func attributed(_ text: String, font: NSFont, color: NSColor,
                            tracking: CGFloat = 0, alignment: NSTextAlignment = .left) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: paragraph
        ])
    }
}
