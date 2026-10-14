import Foundation

public struct PrintRGBColor: Codable, Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }

    public init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789ABCDEFabcdef").contains($0) }),
              let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: UInt8((number >> 16) & 255), green: UInt8((number >> 8) & 255),
                  blue: UInt8(number & 255))
    }

    public var hex: String { String(format: "%02X%02X%02X", red, green, blue) }

    public static let asagi = Self(red: 10, green: 156, blue: 166)
}

public enum PrintDesign: String, CaseIterable, Codable, Sendable {
    case standard, compact
    case largePrint = "large-print"

    public var label: String {
        switch self {
        case .standard: "標準"
        case .compact: "コンパクト"
        case .largePrint: "大きな文字"
        }
    }
}

public struct PrintAppearance: Codable, Equatable, Sendable {
    public var design: PrintDesign
    public var accent: PrintRGBColor
    public var vowelNucleus: PrintRGBColor

    public init(design: PrintDesign = .standard, accent: PrintRGBColor = .asagi,
                vowelNucleus: PrintRGBColor = .asagi) {
        self.design = design
        self.accent = accent
        self.vowelNucleus = vowelNucleus
    }
}
