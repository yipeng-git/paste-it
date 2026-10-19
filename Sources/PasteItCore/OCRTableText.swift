import CoreGraphics
import Foundation

/// Formats detected table cells without guessing columns from ordinary OCR text.
public enum OCRTableText {
    public struct Line: Sendable {
        public let text: String
        public let bounds: CGRect

        public init(text: String, bounds: CGRect) {
            self.text = text
            self.bounds = bounds
        }
    }

    public struct Table: Sendable {
        public let rows: [[String]]
        public let bounds: CGRect

        public init(rows: [[String]], bounds: CGRect) {
            self.rows = rows
            self.bounds = bounds
        }
    }

    public static func markdown(rows: [[String]]) -> String? {
        guard let width = rows.map(\.count).max(), width > 0,
              rows.joined().contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        let formatted = rows.map { row in
            let cells = row.map(escapeCell) + Array(repeating: "", count: width - row.count)
            return "| " + cells.joined(separator: " | ") + " |"
        }
        let separator = "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"
        return ([formatted[0], separator] + formatted.dropFirst()).joined(separator: "\n")
    }

    /// Reuse successful text OCR inside a cell. Lines crossing several cells
    /// belong to document recognition instead of being duplicated in one cell.
    public static func cellText(lines: [Line], bounds: CGRect, fallback: String) -> String {
        let contained = lines.filter { line in
            let area = line.bounds.width * line.bounds.height
            let intersection = line.bounds.intersection(bounds)
            return area > 0 && !intersection.isNull
                && intersection.width * intersection.height / area >= 0.8
        }.sorted {
            if $0.bounds.maxY != $1.bounds.maxY { return $0.bounds.maxY > $1.bounds.maxY }
            return $0.bounds.minX < $1.bounds.minX
        }
        return contained.isEmpty ? fallback : contained.map(\.text).joined(separator: "\n")
    }

    /// Bounds use Vision's normalized, lower-left coordinate system.
    /// Replace text covered by tables, retaining surrounding text in reading order.
    public static func compose(lines: [Line], tables: [Table]) -> String? {
        let rendered = tables.compactMap { table -> (text: String, bounds: CGRect)? in
            guard let text = markdown(rows: table.rows) else { return nil }
            return (text, table.bounds)
        }
        guard !rendered.isEmpty else {
            let text = lines.map(\.text).joined(separator: "\n")
            return text.isEmpty ? nil : text
        }

        var blocks = lines.filter { line in
            !rendered.contains { table in
                let intersection = line.bounds.intersection(table.bounds)
                let area = line.bounds.width * line.bounds.height
                return area > 0 && !intersection.isNull
                    && intersection.width * intersection.height / area >= 0.5
            }
        }.map { (text: $0.text, bounds: $0.bounds, isTable: false) }
        blocks += rendered.map { (text: $0.text, bounds: $0.bounds, isTable: true) }
        blocks.sort {
            if $0.bounds.maxY != $1.bounds.maxY { return $0.bounds.maxY > $1.bounds.maxY }
            return $0.bounds.minX < $1.bounds.minX
        }

        var output = ""
        var previousWasTable = false
        for block in blocks {
            if !output.isEmpty { output += previousWasTable || block.isTable ? "\n\n" : "\n" }
            output += block.text
            previousWasTable = block.isTable
        }
        return output.isEmpty ? nil : output
    }

    private static func escapeCell(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        for character in ["\\", "|", "`", "*", "_", "[", "]"] {
            result = result.replacingOccurrences(of: character, with: "\\" + character)
        }
        return result.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
