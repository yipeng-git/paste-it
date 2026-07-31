import Foundation
import Testing
@testable import PasteItCore

@Suite("LooksLikeNumber")
struct LooksLikeNumberTests {
    @Test(arguments: [
        "42",
        "-7",
        "0",
        "+12",
        "3.14",
        "0.5",
        "3,14",
        "0,5",
        "1,234",
        "1,234,567",
        "1.234",
        "1.234.567",
        "1,234.56",
        "1.234,56",
        "1 234",
        "1 234,56",
        "1'234.56",
        "  99.9  ",
        "-1,234.5",
        "13800138000",
    ])
    func acceptsNumberLiterals(_ sample: String) {
        #expect(LooksLikeNumber.matches(sample))
    }

    @Test(arguments: [
        "",
        "   ",
        "1+2",
        "12 34",
        "1,2,3.4.5",
        "$12",
        "12kg",
        "EUR 1.2",
        "1.2.3",
        "hello",
        "12.34.56",
        "1,,234",
        ",123",
        "123,",
        "+",
        "-",
        ".",
        "1.2,3.4",
    ])
    func rejectsNonNumbers(_ sample: String) {
        #expect(!LooksLikeNumber.matches(sample))
    }
}
