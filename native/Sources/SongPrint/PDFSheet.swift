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
    private var columns: [CGFloat] { [105, 115, 142, contentWidth - 362] }

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
            for phrase in sheet.phrases { drawPhrase(phrase) }
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
        fill(CGRect(x: margin, y: 104, width: contentWidth, height: 1), line)
        y = 122
    }

    private func endPage() {
        fill(CGRect(x: margin, y: footerTop, width: contentWidth, height: 1), line)
        drawText("意味と発音を読み、音節と音符をつなぐ練習帳", x: margin, y: footerTop + 11,
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

    private func drawPhrase(_ phrase: PrintPhrase) {
        let originalHeight = textHeight(phrase.original, width: contentWidth - 24,
                                        font: .systemFont(ofSize: 16, weight: .semibold))
        let translationHeight = textHeight(phrase.translation, width: contentWidth - 24,
                                           font: .systemFont(ofSize: 11))
        let rowsHeight = phrase.words.reduce(CGFloat(0)) { total, word in
            let values = [word.original, word.meaning, word.ipa, word.reading]
            return total + max(30, values.enumerated().map { column, value in
                textHeight(value.isEmpty ? "-" : value, width: columns[column] - 12,
                           font: .systemFont(ofSize: column == 0 ? 10.5 : 9.5)) + 12
            }.max() ?? 30)
        }
        let phraseHeight = originalHeight + translationHeight + 48
            + (phrase.section == section ? 0 : 24) + (phrase.words.isEmpty ? 0 : 23 + rowsHeight)
        // Keep a short phrase with its table; long phrases still flow row by row across pages.
        if phraseHeight < footerTop - 134 && y + phraseHeight > footerTop - 12 {
            endPage(); startPage()
        }
        ensure(max(100, originalHeight + translationHeight + 60))
        if section != phrase.section {
            section = phrase.section
            drawText(section, x: margin, y: y, width: contentWidth,
                     font: .systemFont(ofSize: 10, weight: .bold), color: teal)
            y += 24
        }
        fill(CGRect(x: margin, y: y, width: 3, height: max(28, originalHeight + translationHeight + 12)), teal)
        y += 3
        y += drawText(phrase.original, x: margin + 12, y: y, width: contentWidth - 24,
                      font: .systemFont(ofSize: 16, weight: .semibold), color: dark) + 3
        if !phrase.translation.isEmpty {
            y += drawText(phrase.translation, x: margin + 12, y: y, width: contentWidth - 24,
                          font: .systemFont(ofSize: 11), color: muted) + 6
        } else { y += 7 }
        if !phrase.words.isEmpty {
            drawTableHeader()
            for (index, word) in phrase.words.enumerated() {
                let values = [word.original, word.meaning, word.ipa, word.reading]
                let rowHeight = max(30, values.enumerated().map { column, value in
                    textHeight(value.isEmpty ? "-" : value, width: columns[column] - 12,
                               font: .systemFont(ofSize: column == 0 ? 10.5 : 9.5)) + 12
                }.max() ?? 30)
                if ensure(rowHeight + 4) { drawTableHeader() }
                if index.isMultiple(of: 2) {
                    fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight), pale)
                }
                var x = margin
                for column in 0..<values.count {
                    drawText(values[column].isEmpty ? "-" : values[column], x: x + 6, y: y + 6,
                             width: columns[column] - 12,
                             font: .systemFont(ofSize: column == 0 ? 10.5 : 9.5,
                                               weight: column == 0 ? .medium : .regular),
                             color: column == 0 ? dark : muted)
                    x += columns[column]
                }
                fill(CGRect(x: margin, y: y + rowHeight - 0.5, width: contentWidth, height: 0.5), line)
                y += rowHeight
            }
        }
        y += 22
    }

    private func drawTableHeader() {
        ensure(28)
        fill(CGRect(x: margin, y: y, width: contentWidth, height: 23), teal)
        var x = margin
        for (index, label) in ["語", "意味", "IPA", "カタカナ読み"].enumerated() {
            drawText(label, x: x + 6, y: y + 4, width: columns[index] - 12,
                     font: .systemFont(ofSize: 9, weight: .semibold), color: .white)
            x += columns[index]
        }
        y += 23
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
