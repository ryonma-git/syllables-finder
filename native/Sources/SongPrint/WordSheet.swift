import Foundation

public enum WordSheet {
    public static func render(_ sheet: PrintSheet) throws -> Data {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("song-print-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let files: [String: String] = [
            "[Content_Types].xml": contentTypes,
            "_rels/.rels": rootRelationships,
            "word/document.xml": document(sheet),
            "word/styles.xml": styles,
            "word/_rels/document.xml.rels": documentRelationships,
            "word/header1.xml": header,
            "word/footer1.xml": footer,
            "docProps/core.xml": coreProperties(sheet),
            "docProps/app.xml": appProperties
        ]
        for (path, contents) in files {
            let url = directory.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let archive = fileManager.temporaryDirectory.appendingPathComponent("song-print-\(UUID().uuidString).docx")
        defer { try? fileManager.removeItem(at: archive) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-X", "-r", archive.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw PrintError.archiveFailed }
        return try Data(contentsOf: archive)
    }

    private static func document(_ sheet: PrintSheet) -> String {
        var body = paragraph(sheet.title, style: "Title")
        body += paragraph("青緑は綴り上の母音核の目安。· は音節の区切りです。", style: "Translation")
        if sheet.phrases.isEmpty { body += paragraph("歌詞はまだありません。", style: "Translation") }
        var lastSection = ""
        for phrase in sheet.phrases {
            if phrase.section != lastSection {
                body += paragraph(phrase.section, style: "Section")
                lastSection = phrase.section
            }
            body += paragraph(phrase.original, style: "Phrase")
            if !phrase.translation.isEmpty { body += paragraph("文の意味　" + phrase.translation, style: "Translation", keepNext: true) }
            let rows = flowRows(phrase.words)
            for (index, row) in rows.enumerated() {
                if index > 0 {
                    body += paragraph("続き｜" + phrase.original, style: "Continuation", keepNext: true)
                }
                body += interlinearRow(row.words, widths: row.widths)
                // Word merges consecutive tables with different grids unless a paragraph separates them.
                body += paragraph("", style: "RowGap")
            }
            body += paragraph("", style: "Gap")
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:body>\(body)<w:sectPr><w:headerReference w:type="default" r:id="rId2"/><w:footerReference w:type="default" r:id="rId3"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1170" w:right="1043" w:bottom="1080" w:left="1043" w:header="520" w:footer="520"/></w:sectPr></w:body>
        </w:document>
        """
    }

    private static func flowRows(_ words: [PrintWord]) -> [(words: [PrintWord], widths: [Int])] {
        var rows: [(words: [PrintWord], widths: [Int])] = []
        var row: [PrintWord] = []
        var widths: [Int] = []
        var used = 0
        for word in words {
            let width = min(2500, max(1100, word.segmented.count * 205,
                                      word.meaning.count * 155,
                                      word.ipa.count * 105,
                                      word.reading.count * 145) + 150)
            if !row.isEmpty && (row.count >= 8 || used + width > 9000) {
                rows.append((row, widths)); row = []; widths = []; used = 0
            }
            row.append(word); widths.append(width); used += width
        }
        if !row.isEmpty { rows.append((row, widths)) }
        return rows
    }

    private static func interlinearRow(_ words: [PrintWord], widths: [Int]) -> String {
        let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        let cells = zip(words, widths).map { word, width in
            """
            <w:tc><w:tcPr><w:tcW w:w="\(width)" w:type="dxa"/>
            <w:tcMar><w:top w:w="25" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="25" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tcMar></w:tcPr>
            \(paragraph(word.meaning.isEmpty ? "意味未設定" : word.meaning, style: "Gloss"))
            \(syllableParagraph(word))
            \(paragraph(word.ipa.isEmpty ? "IPA未設定" : word.ipa, style: "Annotation"))
            \(paragraph(word.reading.isEmpty ? "読み未設定" : word.reading, style: "Annotation"))
            </w:tc>
            """
        }.joined()
        return """
        <w:tbl><w:tblPr><w:tblW w:w="\(widths.reduce(0, +))" w:type="dxa"/><w:tblLayout w:type="fixed"/>
        <w:tblInd w:w="420" w:type="dxa"/><w:tblCellSpacing w:w="0" w:type="dxa"/></w:tblPr>
        <w:tblGrid>\(grid)</w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr>\(cells)</w:tr></w:tbl>
        """
    }

    private static func syllableParagraph(_ word: PrintWord) -> String {
        let runs = word.displayFragments.map { segment in
            "<w:r><w:rPr><w:b/><w:color w:val=\"\(segment.isVowelNucleus ? "0A9CA6" : "242424")\"/></w:rPr><w:t xml:space=\"preserve\">\(escape(segment.text))</w:t></w:r>"
        }.joined()
        return "<w:p><w:pPr><w:pStyle w:val=\"Lyric\"/></w:pPr>\(runs)</w:p>"
    }

    private static func paragraph(_ text: String, style: String, keepNext: Bool = false) -> String {
        let parts = text.components(separatedBy: .newlines).map { "<w:t xml:space=\"preserve\">\(escape($0))</w:t>" }.joined(separator: "<w:br/>")
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>\(keepNext || style == "Phrase" || style == "Section" ? "<w:keepNext/>" : "")</w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"Hiragino Sans\" w:hAnsi=\"Hiragino Sans\" w:eastAsia=\"Hiragino Sans\"/><w:lang w:eastAsia=\"ja-JP\"/></w:rPr>\(parts)</w:r></w:p>"
    }

    private static func escape(_ text: String) -> String {
        let allowed = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return value == 9 || value == 10 || value == 13 || value >= 32
        }))
        return allowed.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
      <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
      <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """
    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """
    private static let documentRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
    </Relationships>
    """
    private static let header = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr><w:r><w:t>SINGING WORKSPACE</w:t></w:r></w:p></w:hdr>
    """
    private static let footer = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr>
    <w:r><w:t>意味と発音を読み、音節と音符をつなぐ練習帳</w:t></w:r><w:r><w:tab/></w:r>
    <w:fldSimple w:instr="PAGE"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>
    """
    private static func coreProperties(_ sheet: PrintSheet) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(escape(sheet.title))</dc:title><dc:creator>Singing Workspace</dc:creator></cp:coreProperties>
        """
    }
    private static let appProperties = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Singing Workspace</Application></Properties>
    """
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Hiragino Sans" w:hAnsi="Hiragino Sans" w:eastAsia="Hiragino Sans"/><w:lang w:eastAsia="ja-JP"/><w:sz w:val="20"/><w:color w:val="242424"/></w:rPr></w:rPrDefault></w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:pPr><w:spacing w:after="100"/></w:pPr></w:style>
      <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="0" w:after="300"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:color w:val="242424"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Section"><w:name w:val="Section"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="220" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="20"/><w:color w:val="0A9CA6"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Phrase"><w:name w:val="Phrase"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="110" w:after="70"/></w:pPr><w:rPr><w:b/><w:sz w:val="27"/><w:color w:val="242424"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Translation"><w:name w:val="Translation"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="130"/></w:pPr><w:rPr><w:sz w:val="20"/><w:color w:val="686868"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Gloss"><w:name w:val="Gloss"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="15"/></w:pPr><w:rPr><w:sz w:val="16"/><w:color w:val="686868"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Lyric"><w:name w:val="Lyric"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="10"/></w:pPr><w:rPr><w:b/><w:sz w:val="23"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Annotation"><w:name w:val="Annotation"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:sz w:val="16"/><w:color w:val="686868"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Continuation"><w:name w:val="Continuation"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="55" w:after="15"/></w:pPr><w:rPr><w:sz w:val="16"/><w:color w:val="0A9CA6"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="RowGap"><w:name w:val="RowGap"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="0" w:after="0"/><w:keepNext/></w:pPr><w:rPr><w:sz w:val="4"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Gap"><w:name w:val="Gap"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="50"/></w:pPr><w:rPr><w:sz w:val="6"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Header"><w:name w:val="Header"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="16"/><w:color w:val="0A9CA6"/><w:spacing w:val="20"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="Footer"/><w:basedOn w:val="Normal"/><w:pPr><w:tabs><w:tab w:val="right" w:pos="9800"/></w:tabs></w:pPr><w:rPr><w:sz w:val="15"/><w:color w:val="686868"/></w:rPr></w:style>
    </w:styles>
    """
}
