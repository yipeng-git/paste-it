import Foundation

/// Content heuristic: the entire trimmed string looks like a single number literal.
///
/// Accepts US (`1,234.56`) and EU (`1.234,56`) grouping/decimal conventions,
/// space / narrow-space / apostrophe thousands separators, and an optional leading sign.
/// Does not accept currency, units, formulas, or version-like multi-dot forms (`1.2.3`).
public enum LooksLikeNumber {
    private static let softGrouping: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "'"]

    public static func matches(_ raw: String) -> Bool {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }

        if s.first == "+" || s.first == "-" {
            s.removeFirst()
            guard !s.isEmpty else { return false }
        }

        guard let first = s.first, first.isNumber else { return false }

        let dotCount = s.reduce(into: 0) { count, ch in if ch == "." { count += 1 } }
        let commaCount = s.reduce(into: 0) { count, ch in if ch == "," { count += 1 } }

        if dotCount > 0, commaCount > 0 {
            guard let decimal = rightmostDecimalSeparator(in: s) else { return false }
            let thousand: Character = decimal == "." ? "," : "."
            return validate(s, thousandSeparators: [thousand], decimal: decimal)
        }

        if dotCount > 0 || commaCount > 0 {
            let sep: Character = dotCount > 0 ? "." : ","
            if validate(s, thousandSeparators: [sep], decimal: nil) { return true }
            if validate(s, thousandSeparators: [], decimal: sep) { return true }
            if validate(s, thousandSeparators: softGrouping, decimal: sep) { return true }
            return false
        }

        if s.allSatisfy(\.isNumber) { return true }
        if validate(s, thousandSeparators: softGrouping, decimal: nil) { return true }
        return false
    }

    private static func rightmostDecimalSeparator(in s: String) -> Character? {
        guard let lastDot = s.lastIndex(of: "."), let lastComma = s.lastIndex(of: ",") else {
            return nil
        }
        return lastDot > lastComma ? "." : ","
    }

    private static func validate(
        _ s: String,
        thousandSeparators: Set<Character>,
        decimal: Character?
    ) -> Bool {
        let intPart: Substring
        let fracPart: Substring?

        if let decimal {
            guard let idx = s.lastIndex(of: decimal) else { return false }
            guard s.firstIndex(of: decimal) == idx else { return false }
            intPart = s[..<idx]
            let frac = s[s.index(after: idx)...]
            guard !frac.isEmpty, frac.allSatisfy(\.isNumber) else { return false }
            fracPart = frac
        } else {
            intPart = Substring(s)
            fracPart = nil
        }

        _ = fracPart
        guard !intPart.isEmpty else { return false }

        if thousandSeparators.isEmpty {
            return intPart.allSatisfy(\.isNumber)
        }

        var groups: [String] = []
        var current = ""
        for ch in intPart {
            if thousandSeparators.contains(ch) {
                guard !current.isEmpty else { return false }
                groups.append(current)
                current = ""
            } else if ch.isNumber {
                current.append(ch)
            } else {
                return false
            }
        }
        guard !current.isEmpty else { return false }
        groups.append(current)

        guard let leading = groups.first, (1...3).contains(leading.count) else { return false }
        for group in groups.dropFirst() {
            guard group.count == 3 else { return false }
        }
        // A lone group with no separators is handled by the allSatisfy digits path;
        // requiring at least one separator when thousandSeparators is non-empty avoids
        // treating plain "12" as a grouped form (still fine) but "12 34" fails grouping.
        return groups.count >= 1
    }
}
