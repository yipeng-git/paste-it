import Foundation
import Testing
@testable import PasteItCore

@Suite("FilterCategory")
struct FilterCategoryTests {
    @Test
    func textExcludesNumbers() {
        #expect(FilterCategory.text.matches(primaryTypeRaw: "text", plainText: "hello"))
        #expect(!FilterCategory.text.matches(primaryTypeRaw: "text", plainText: "1,234.56"))
        #expect(FilterCategory.number.matches(primaryTypeRaw: "text", plainText: "1,234.56"))
        #expect(FilterCategory.number.matches(primaryTypeRaw: "html", plainText: "42"))
    }

    @Test
    func linkImageFile() {
        #expect(FilterCategory.link.matches(primaryTypeRaw: "url", plainText: "x"))
        #expect(FilterCategory.image.matches(primaryTypeRaw: "image", plainText: ""))
        #expect(FilterCategory.file.matches(primaryTypeRaw: "file", plainText: "/tmp/a"))
        #expect(!FilterCategory.file.matches(primaryTypeRaw: "image", plainText: ""))
    }

    @Test
    func mixedOnlyInAll() {
        #expect(FilterCategory.all.matches(primaryTypeRaw: "mixed", plainText: "x"))
        #expect(!FilterCategory.text.matches(primaryTypeRaw: "mixed", plainText: "x"))
        #expect(!FilterCategory.number.matches(primaryTypeRaw: "mixed", plainText: "1"))
    }

    @Test
    func typeTokenParsing() {
        #expect(FilterCategory.from(typeToken: "link") == .link)
        #expect(FilterCategory.from(typeToken: "url") == .link)
        #expect(FilterCategory.from(typeToken: "number") == .number)
        #expect(FilterCategory.from(typeToken: "folder") == .file)
        #expect(FilterCategory.from(typeToken: "html") == .text)
    }
}
