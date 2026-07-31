import Foundation
import Testing
@testable import PasteItCore

@Suite("ClipTypeResolver")
struct ClipTypeResolveTests {
    @Test
    func fileURLWinsOverImagePreview() {
        let result = ClipTypeResolver.resolve(
            .init(
                fileURLs: [URL(fileURLWithPath: "/tmp/photo.png")],
                plainText: "/tmp/photo.png",
                hasImageData: true
            )
        )
        #expect(result.primaryTypeRaw == "file")
        #expect(result.fileURLStrings.count == 1)
    }

    @Test
    func imageWithoutFileURL() {
        let result = ClipTypeResolver.resolve(
            .init(plainText: "", hasImageData: true)
        )
        #expect(result.primaryTypeRaw == "image")
    }

    @Test
    func fileSchemeTextIsNotLink() {
        #expect(!ClipTypeResolver.looksLikeWebURL("file:///Users/me/doc.pdf"))
        let result = ClipTypeResolver.resolve(
            .init(plainText: "file:///Users/me/doc.pdf")
        )
        #expect(result.primaryTypeRaw == "text")
    }

    @Test
    func httpTextIsLink() {
        #expect(ClipTypeResolver.looksLikeWebURL("https://pasly.app"))
        let result = ClipTypeResolver.resolve(
            .init(plainText: "https://pasly.app")
        )
        #expect(result.primaryTypeRaw == "url")
    }

    @Test
    func multiFileStaysFile() {
        let result = ClipTypeResolver.resolve(
            .init(
                fileURLs: [
                    URL(fileURLWithPath: "/tmp/a.txt"),
                    URL(fileURLWithPath: "/tmp/b.txt"),
                ],
                hasImageData: true
            )
        )
        #expect(result.primaryTypeRaw == "file")
        #expect(result.fileURLStrings.count == 2)
        #expect(result.isDirectory == false)
    }

    @Test
    func directoryFlagForTrailingSlash() {
        let result = ClipTypeResolver.resolve(
            .init(fileURLs: [URL(fileURLWithPath: "/tmp/folder/", isDirectory: true)])
        )
        #expect(result.primaryTypeRaw == "file")
        #expect(result.isDirectory == true)
    }

    @Test
    func rtfAndHtmlPriorityWithoutFiles() {
        #expect(
            ClipTypeResolver.resolve(.init(plainText: "x", hasHTML: true, hasRTF: true))
                .primaryTypeRaw == "richText"
        )
        #expect(
            ClipTypeResolver.resolve(.init(plainText: "x", hasHTML: true))
                .primaryTypeRaw == "html"
        )
    }
}
