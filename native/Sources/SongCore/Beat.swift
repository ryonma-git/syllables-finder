import Foundation

public enum SongError: Error, Equatable, LocalizedError, Sendable {
    case invalid(String)
    case unsupportedVersion(Int)
    case staleAnalysis

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .unsupportedVersion(let version): "この文書の形式（version \(version)）には対応していません。"
        case .staleAnalysis: "解析中に文書が変更されました。現在の編集を保持しました。もう一度解析してください。"
        }
    }
}

/// Exact quarter-note units. Bounds keep comparisons and arithmetic within Int64.
public struct Beat: Codable, Hashable, Comparable, Sendable {
    public let numerator: Int64
    public let denominator: Int64
    public static let zero = Beat(whole: 0)

    public init(_ numerator: Int64, _ denominator: Int64 = 1) throws {
        guard numerator >= 0, denominator > 0,
              numerator <= 1_000_000_000, denominator <= 1_000_000_000 else {
            throw SongError.invalid("拍の値が有効な範囲を超えています。")
        }
        let divisor = Self.gcd(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    private init(whole: Int64) { numerator = whole; denominator = 1 }

    public var doubleValue: Double { Double(numerator) / Double(denominator) }
    public static func < (lhs: Beat, rhs: Beat) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    public func adding(_ other: Beat) throws -> Beat {
        let divisor = Self.gcd(denominator, other.denominator)
        let den = denominator * (other.denominator / divisor)
        let num = numerator * (other.denominator / divisor) + other.numerator * (denominator / divisor)
        let reduced = Self.gcd(num, den)
        return try Beat(num / reduced, den / reduced)
    }

    /// Throws when the result would be negative.
    public func subtracting(_ other: Beat) throws -> Beat {
        let divisor = Self.gcd(denominator, other.denominator)
        let den = denominator * (other.denominator / divisor)
        let num = numerator * (other.denominator / divisor) - other.numerator * (denominator / divisor)
        guard num >= 0 else { throw SongError.invalid("拍の差が負になりました。") }
        let reduced = Self.gcd(num, den)
        return try Beat(num / reduced, den / reduced)
    }

    /// UI-only conversion; import adapters must construct from original integer ticks/divisions.
    public static func grid(_ value: Double, divisions: Int64 = 960) throws -> Beat {
        guard value.isFinite, divisions > 0, divisions <= 1_000_000_000,
              value >= 0, value * Double(divisions) <= 1_000_000_000 else {
            throw SongError.invalid("拍には有効な正の数を入力してください。")
        }
        return try Beat(Int64((value * Double(divisions)).rounded()), divisions)
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a; var b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(c.decode(Int64.self, forKey: .numerator), c.decode(Int64.self, forKey: .denominator))
    }
}

public struct BeatRange: Codable, Hashable, Sendable {
    public var start: Beat
    public var end: Beat
    public init(start: Beat, end: Beat) { self.start = start; self.end = end }
    public var length: Double { end.doubleValue - start.doubleValue }
    public func contains(_ other: BeatRange) -> Bool { start <= other.start && other.end <= end }
    public func validate() throws {
        guard start < end else { throw SongError.invalid("時間範囲の終了は開始より後にしてください。") }
    }
}
