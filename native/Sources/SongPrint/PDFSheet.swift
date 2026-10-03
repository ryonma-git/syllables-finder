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
    private let pale = NSColor(calibratedRed: 0.95, green: 0.985, blue: 0.986, alpha: 1)
    private let margin: CGFloat = 46
    private var page = 0
    private var y: CGFloat = 0
    private var priorGraphics: NSGraphicsContext?
    private var section = ""
    private var contentWidth: CGFloat { size.width - 2 * margin }
    private var footerTop: CGFloat { size.height - 54 }
    private let wordColumns = 4
    private var wordWidth: CGFloat { contentWidth / CGFloat(wordColumns) }

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
        drawText("SINGING WORKSPACE", x: margin, y: 34, width: contentWidth,
                 font: .systemFont(ofSize: 9, weight: .semibold), color: teal, tracking: 1.6)
        drawText(title, x: margin, y: 52, width: contentWidth,
                 font: .systemFont(ofSize: 22, weight: .semibold), color: dark)
        drawText("原文  /  音節  /  IPA  /  カタカナ  /  語の意味  /  文の意味", x: margin, y: 85,
                 width: contentWidth, font: .systemFont(ofSize: 9), color: muted)
        fill(CGRect(x: margin, y: 108, width: contentWidth, height: 1), line)
        y = 125
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
        let headingHeight = textHeight(phrase.original, width: contentWidth - 12,
                                       font: .systemFont(ofSize: 14, weight: .semibold)) + 27
        let groups = stride(from: 0, to: phrase.words.count, by: wordColumns).map {
            Array(phrase.words[$0..<min($0 + wordColumns, phrase.words.count)])
        }
        let rowHeights = groups.map { group in max(72, group.map(wordHeight).max() ?? 72) }
        let translationHeight = phrase.translation.isEmpty ? 0 :
            textHeight(phrase.translation, width: contentWidth - 100, font: .systemFont(ofSize: 10.5)) + 16
        let wholeHeight = headingHeight + rowHeights.reduce(0, +) + CGFloat(translationHeight) + 26
            + (phrase.section == section ? 0 : 24)
        if wholeHeight < footerTop - 135 && y + wholeHeight > footerTop - 12 { endPage(); startPage() }
        ensure(headingHeight + (rowHeights.first ?? 0) + 20)
        if section != phrase.section {
            section = phrase.section
            drawText(section, x: margin, y: y, width: contentWidth,
                     font: .systemFont(ofSize: 10, weight: .bold), color: teal)
            y += 24
        }
        drawText(String(format: "%02d", index + 1), x: margin, y: y + 1, width: 28,
                 font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: teal)
        y += drawText(phrase.original, x: margin + 30, y: y, width: contentWidth - 30,
                      font: .systemFont(ofSize: 14, weight: .semibold), color: dark) + 12
        for (rowIndex, group) in groups.enumerated() {
            let height = rowHeights[rowIndex]
            if ensure(height + 4) {
                drawText("\(phrase.section)  /  \(String(format: "%02d", index + 1))（続き）",
                         x: margin, y: y, width: contentWidth,
                         font: .systemFont(ofSize: 9, weight: .semibold), color: teal)
                y += 18
            }
            if rowIndex.isMultiple(of: 2) {
                fill(CGRect(x: margin, y: y, width: contentWidth, height: height), pale)
            }
            for (column, word) in group.enumerated() {
                drawWord(word, x: margin + CGFloat(column) * wordWidth, y: y)
                if column > 0 {
                    fill(CGRect(x: margin + CGFloat(column) * wordWidth, y: y + 8,
                                width: 0.5, height: height - 16), line)
                }
            }
            fill(CGRect(x: margin, y: y + height - 0.5, width: contentWidth, height: 0.5), line)
            y += height
        }
        if !phrase.translation.isEmpty {
            ensure(CGFloat(translationHeight) + 7)
            drawText("文の意味", x: margin + 7, y: y + 10, width: 65,
                     font: .systemFont(ofSize: 9, weight: .semibold), color: teal)
            drawText(phrase.translation, x: margin + 73, y: y + 8, width: contentWidth - 80,
                     font: .systemFont(ofSize: 10.5), color: dark)
            y += CGFloat(translationHeight)
        }
        y += 24
    }

    private func wordHeight(_ word: PrintWord) -> CGFloat {
        let width = wordWidth - 14
        return 14 + textHeight(word.meaning.isEmpty ? "意味未設定" : word.meaning, width: width,
                               font: .systemFont(ofSize: 9))
            + richHeight(segmented(word), width: width)
            + textHeight(word.ipa.isEmpty ? "IPA未設定" : word.ipa, width: width,
                         font: .systemFont(ofSize: 9))
            + textHeight(word.reading.isEmpty ? "読み未設定" : word.reading, width: width,
                         font: .systemFont(ofSize: 9.5)) + 7
    }

    private func drawWord(_ word: PrintWord, x: CGFloat, y: CGFloat) {
        let width = wordWidth - 14
        var top = y + 8
        top += drawText(word.meaning.isEmpty ? "意味未設定" : word.meaning,
                        x: x + 7, y: top, width: width, font: .systemFont(ofSize: 9), color: muted) + 2
        let segmented = segmented(word)
        let height = richHeight(segmented, width: width)
        segmented.draw(with: CGRect(x: x + 7, y: top, width: width, height: height),
                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        top += height + 2
        top += drawText(word.ipa.isEmpty ? "IPA未設定" : word.ipa,
                        x: x + 7, y: top, width: width, font: .systemFont(ofSize: 9), color: dark) + 2
        drawText(word.reading.isEmpty ? "読み未設定" : word.reading,
                 x: x + 7, y: top, width: width, font: .systemFont(ofSize: 9.5), color: muted)
    }

    private func segmented(_ word: PrintWord) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let basic: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dark]
        if word.syllables.isEmpty {
            result.append(NSAttributedString(string: word.original, attributes: basic))
        } else {
            for (index, syllable) in word.syllables.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "·", attributes: [.font: font, .foregroundColor: muted])) }
                for fragment in syllable.fragments {
                    result.append(NSAttributedString(string: fragment.text, attributes: [
                        .font: font, .foregroundColor: fragment.isVowelNucleus ? teal : dark
                    ]))
                }
            }
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
