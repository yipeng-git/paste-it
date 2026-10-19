import Foundation
import Testing
@testable import PasteItCore

struct OCRTableTextTests {
    @Test func preservesEmptyCellsAndPadsShortRows() {
        #expect(OCRTableText.markdown(rows: [
            ["Item", "Quantity", "Price"], ["Tea", "", "48"], ["Coffee"]
        ]) == """
        | Item | Quantity | Price |
        | --- | --- | --- |
        | Tea |  | 48 |
        | Coffee |  |  |
        """)
    }

    @Test func escapesCellContentWithoutAddingColumnsOrRows() {
        #expect(OCRTableText.markdown(rows: [["A | B", "<tag> & C"], ["one\r\ntwo", "C:\\temp"]]) == """
        | A \\| B | &lt;tag&gt; &amp; C |
        | --- | --- |
        | one<br>two | C:\\\\temp |
        """)
    }

    @Test func preservesMultilingualAndSpanningCellAnchors() {
        #expect(OCRTableText.markdown(rows: [
            ["名称 / 品目", "数量"], ["合并单元格", ""], ["", "12"]
        ]) == """
        | 名称 / 品目 | 数量 |
        | --- | --- |
        | 合并单元格 |  |
        |  | 12 |
        """)
    }

    @Test func ignoresEmptyDetections() {
        #expect(OCRTableText.markdown(rows: []) == nil)
        #expect(OCRTableText.markdown(rows: [[]]) == nil)
        #expect(OCRTableText.markdown(rows: [[" ", "\n"], ["", ""]]) == nil)
    }

    @Test func reusesExistingOCRAndKeepsMultilineCellOrder() {
        let bounds = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.6)
        let lines = [
            OCRTableText.Line(text: "12", bounds: CGRect(x: 0.15, y: 0.2, width: 0.1, height: 0.1)),
            OCRTableText.Line(text: "数量", bounds: CGRect(x: 0.15, y: 0.5, width: 0.1, height: 0.1)),
            OCRTableText.Line(text: "Other cell", bounds: CGRect(x: 0.6, y: 0.5, width: 0.2, height: 0.1))
        ]
        #expect(OCRTableText.cellText(lines: lines, bounds: bounds, fallback: "") == "数量\n12")
        #expect(OCRTableText.cellText(lines: [], bounds: bounds, fallback: "Native result") == "Native result")
    }

    @Test func doesNotPutAnEntireCrossColumnLineIntoOneCell() {
        let line = OCRTableText.Line(text: "Tea 12 48", bounds: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.1))
        #expect(OCRTableText.cellText(lines: [line], bounds: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.3),
                                     fallback: "Tea") == "Tea")
    }

    @Test func retainsSurroundingTextAndReplacesTableLinesOnlyOnce() {
        let table = OCRTableText.Table(rows: [["Item", "Count"], ["Tea", "8"]],
                                      bounds: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4))
        let lines = [
            OCRTableText.Line(text: "Footer", bounds: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.05)),
            OCRTableText.Line(text: "Tea 8", bounds: CGRect(x: 0.15, y: 0.35, width: 0.5, height: 0.05)),
            OCRTableText.Line(text: "Report", bounds: CGRect(x: 0.1, y: 0.85, width: 0.4, height: 0.05)),
            OCRTableText.Line(text: "Item Count", bounds: CGRect(x: 0.15, y: 0.6, width: 0.5, height: 0.05))
        ]
        #expect(OCRTableText.compose(lines: lines, tables: [table]) == """
        Report

        | Item | Count |
        | --- | --- |
        | Tea | 8 |

        Footer
        """)
    }

    @Test func emitsMultipleTablesInReadingOrder() {
        let lower = OCRTableText.Table(rows: [["Lower"], ["2"]],
                                      bounds: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2))
        let upper = OCRTableText.Table(rows: [["Upper"], ["1"]],
                                      bounds: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.2))
        #expect(OCRTableText.compose(lines: [], tables: [lower, upper]) == """
        | Upper |
        | --- |
        | 1 |

        | Lower |
        | --- |
        | 2 |
        """)
    }

    @Test func plainTextFallbackKeepsOriginalObservationOrder() {
        let lines = [
            OCRTableText.Line(text: "First", bounds: CGRect(x: 0, y: 0, width: 1, height: 0.1)),
            OCRTableText.Line(text: "Second", bounds: CGRect(x: 0, y: 0.8, width: 1, height: 0.1))
        ]
        #expect(OCRTableText.compose(lines: lines, tables: []) == "First\nSecond")
        let empty = OCRTableText.Table(rows: [[""]], bounds: .zero)
        #expect(OCRTableText.compose(lines: lines, tables: [empty]) == "First\nSecond")
        #expect(OCRTableText.compose(lines: [], tables: []) == nil)
    }
}
