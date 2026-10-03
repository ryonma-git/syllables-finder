import AppKit
import CoreGraphics
import Foundation

@MainActor
public enum PDFSheet {
    public static func render(_ sheet: PrintSheet) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw PrintError.creationFailed }
        var paper = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // ISO A4, points
        guard let context = CGContext(consumer: consumer, mediaBox: &paper, nil) else {
            throw PrintError.creationFailed
        }
        let painter = PDFPainter(context: context, title: sheet.title, pageSize: paper.size)
        painter.render(sheet)
        context.closePDF()
        return output as Data
    }
}

public enum PrintError: Error, LocalizedError {
    case creationFailed
    case archiveFailed

    public var errorDescription: String? {
        switch self {
        case .creationFailed: "印刷用PDFを作成できませんでした。"
        case .archiveFailed: "Wordファイルを作成できませんでした。"
        }
    }
}

@MainActor
private final class PDFPainter {
    private let context: CGContext
    private let title: String
    private let size: CGSize
    private let teal = NSColor(calibratedRed: 0.05, green: 0.61, blue: 0.65, alpha: 1)
    private let dark = NSColor(calibratedWhite: 0.14, alpha: 1)
    private let muted = NSColor(calibratedWhite: 0.39, alpha: 1)
    private let line = NSColor(calibratedWhite: 0.85, alpha: 1)
    private let margin: CGFloat = 40
    private var page = 0
    private var y: CGFloat = 0
    private var priorGraphics: NSGraphicsContext?
    private var section = ""
    private var contentWidth: CGFloat { size.width - 2 * margin }
    private var footerTop: CGFloat { size.height - 42 }
    private let wordGap: CGFloat = 7

    init(context: CGContext, title: String, pageSize: CGSize) {
        self.context = context; self.title = title; self.size = pageSize
    }

    func render(_ sheet: PrintSheet) {
        startPage()
        if sheet.phrases.isEmpty {
            y += 24
            drawText("歌詞はまだありません。", x: margin, y: y, width: contentWidth,
                     font: .systemFont(ofSize: 13), color: muted)
        } else {
            for (index, phrase) in sheet.phrases.enumerated() { drawPhrase(phrase, index: index) }
        }
        endPage()
    }

    private func startPage() {
        page += 1
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        priorGraphics = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawText("SINGING WORKSPACE", x: margin, y: 22, width: contentWidth,
                 font: .systemFont(ofSize: 9, weight: .semibold), color: teal, tracking: 1.6)
        drawText(title, x: margin, y: 38, width: contentWidth,
                 font: .systemFont(ofSize: 20, weight: .semibold), color: dark)
        drawText("原文  /  音節  /  IPA  /  カタカナ  /  語の意味  /  文の意味", x: margin, y: 70,
                 width: contentWidth, font: .systemFont(ofSize: 9), color: muted)
        fill(CGRect(x: margin, y: 91, width: contentWidth, height: 1), line)
        y = 101
    }

    private func endPage() {
        fill(CGRect(x: margin, y: footerTop, width: contentWidth, height: 1), line)
        drawText("青緑は綴り上の母音核の目安  ·  は音節の区切り", x: margin, y: footerTop + 11,
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
        guard y + height > footerTop - 12 else { return false }
        endPage(); startPage()
        return true
    }

    private func drawPhrase(_ phrase: PrintPhrase, index: Int) {
        let rows = flow(phrase.words)
        let headingHeight = textHeight(phrase.original, width: contentWidth - 30,
                                       font: .systemFont(ofSize: 14, weight: .semibold)) + 6
        let translationHeight = phrase.translation.isEmpty ? 0 :
            textHeight(phrase.translation, width: contentWidth - 78, font: .systemFont(ofSize: 10)) + 5
        let wholeHeight = headingHeight + rows.reduce(CGFloat(0)) { $0 + $1.height + 4 }
            + CGFloat(translationHeight) + 10 + (phrase.section == section ? 0 : 16)
        if wholeHeight < footerTop - 111 && y + wholeHeight > footerTop - 10 { endPage(); startPage() }
        ensure(headingHeight + (rows.first?.height ?? 0) + 8)
        if section != phrase.section {
            section = phrase.section
            drawText(section, x: margin, y: y, width: contentWidth,
                     font: .systemFont(ofSize: 10, weight: .bold), color: teal)
            y += 16
        }
        drawText(String(format: "%02d", index + 1), x: margin, y: y + 1, width: 28,
                 font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: teal)
        y += drawText(phrase.original, x: margin + 30, y: y, width: contentWidth - 30,
                      font: .systemFont(ofSize: 14, weight: .semibold), color: dark) + 6
        for row in rows {
            if ensure(row.height + 5) {
                drawText("\(phrase.section)  /  \(String(format: "%02d", index + 1))（続き）",
                         x: margin, y: y, width: contentWidth,
                         font: .systemFont(ofSize: 9, weight: .semibold), color: teal)
                y += 18
            }
            var x = margin + 30
            for (word, width) in zip(row.words, row.widths) {
                drawWord(word, x: x, y: y, width: width, row: row)
                x += width + wordGap
            }
            y += row.height + 4
        }
        if !phrase.translation.isEmpty {
            ensure(CGFloat(translationHeight) + 5)
            drawText("文の意味", x: margin + 30, y: y + 2, width: 54,
                     font: .systemFont(ofSize: 9, weight: .semibold), color: teal)
            drawText(phrase.translation, x: margin + 84, y: y, width: contentWidth - 84,
                     font: .systemFont(ofSize: 10), color: dark)
            y += CGFloat(translationHeight)
        }
        y += 10
    }

    private struct WordRow {
        var words: [PrintWord]
        var widths: [CGFloat]
        var meaningHeight: CGFloat
        var lyricHeight: CGFloat
        var ipaHeight: CGFloat
        var readingHeight: CGFloat
        var height: CGFloat { meaningHeight + lyricHeight + ipaHeight + readingHeight + 5 }
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
                    width: $0.1, font: .systemFont(ofSize: 8.5)) }.max() ?? 0,
                lyricHeight: zip(current, widths).map { richHeight(segmented($0.0), width: $0.1) }.max() ?? 18,
                ipaHeight: zip(current, widths).map { textHeight($0.0.ipa.isEmpty ? "IPA未設定" : $0.0.ipa,
                    width: $0.1, font: .systemFont(ofSize: 8.5)) }.max() ?? 0,
                readingHeight: zip(current, widths).map { textHeight($0.0.reading.isEmpty ? "カタカナ未設定" : $0.0.reading,
                    width: $0.1, font: .systemFont(ofSize: 8.5)) }.max() ?? 0))
            current = []; widths = []; used = 0
        }
        for word in words {
            let lyric = segmented(word).size().width
            let annotation = [word.meaning, word.ipa, word.reading]
                .map { attributed($0, font: .systemFont(ofSize: 8.5), color: muted).size().width }
                .max() ?? 0
            let width = min(170, max(24, lyric, annotation) + 4)
            if !current.isEmpty && used + wordGap + width > contentWidth - 30 { finish() }
            if !current.isEmpty { used += wordGap }
            current.append(word); widths.append(width); used += width
        }
        finish()
        return rows
    }

    private func drawWord(_ word: PrintWord, x: CGFloat, y: CGFloat, width: CGFloat, row: WordRow) {
        drawText(word.meaning.isEmpty ? "意味未設定" : word.meaning,
                 x: x, y: y, width: width, font: .systemFont(ofSize: 8.5), color: muted)
        let lyric = segmented(word)
        lyric.draw(with: CGRect(x: x, y: y + row.meaningHeight + 2,
                               width: width, height: row.lyricHeight),
                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let ipaY = y + row.meaningHeight + row.lyricHeight + 3
        drawText(word.ipa.isEmpty ? "IPA未設定" : word.ipa,
                 x: x, y: ipaY, width: width, font: .systemFont(ofSize: 8.5), color: dark)
        drawText(word.reading.isEmpty ? "カタカナ未設定" : word.reading,
                 x: x, y: ipaY + row.ipaHeight + 2, width: width,
                 font: .systemFont(ofSize: 8.5), color: muted)
    }

    private func segmented(_ word: PrintWord) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        for fragment in word.displayFragments {
            result.append(NSAttributedString(string: fragment.text, attributes: [
                .font: font, .foregroundColor: fragment.isVowelNucleus ? teal : dark
            ]))
        }
        return result
    }

    private func richHeight(_ value: NSAttributedString, width: CGFloat) -> CGFloat {
        max(18, ceil(value.boundingRect(with: NSSize(width: width, height: 10_000),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
    }

    private func fill(_ rect: CGRect, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let value = attributed(text, font: font, color: dark)
        return max(font.pointSize + 3, ceil(value.boundingRect(with: NSSize(width: width, height: 10_000),
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
        paragraph.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: paragraph
        ])
    }
}
