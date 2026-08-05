import Foundation
import Testing
@testable import PasteItCore

@Suite("ClipPreviewText — card vs Space preview alignment")
struct ClipPreviewTextTests {
    @Test
    func plainTextPreferredOverRich() {
        let resolved = ClipPreviewText.resolve(
            plainText: "hello from plain",
            richPlainText: "ignored rich",
            hasRichPayload: true,
            ocrText: nil,
            fileURLString: nil,
            typeTitle: "HTML"
        )
        #expect(resolved == "hello from plain")
    }

    @Test
    func htmlOnlyUsesRichPlainSoCardMatchesPreview() {
        // Repro: Chrome IP clip — empty plainText, HTML body "0.7.187.231"
        let html = #"<meta charset='utf-8'><article><span>0.7.187.231</span></article>"#
        let richPlain = RichPlainText.extract(htmlText: html, rtfData: nil)
        #expect(richPlain == "0.7.187.231")

        let cardText = ClipPreviewText.resolve(
            plainText: "",
            richPlainText: richPlain,
            hasRichPayload: true,
            ocrText: nil,
            fileURLString: nil,
            typeTitle: "HTML"
        )
        #expect(cardText == "0.7.187.231")
        #expect(cardText == richPlain, "Card text must equal preview plain extraction")
        #expect(ClipPreviewText.characterFooter(forPreviewText: cardText) == "11 characters")
    }

    @Test
    func whitespaceOnlyHtmlDoesNotShowTypeTitle() {
        // Repro: Chrome nbsp-only clip titled "HTML" with plainText " "
        let html = """
        <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
        <html><body><p><span class="Apple-converted-space">\u{00A0}</span></p></body></html>
        """
        let richPlain = RichPlainText.extract(htmlText: html, rtfData: nil)
        #expect(richPlain.isEmpty)

        let cardText = ClipPreviewText.resolve(
            plainText: " ",
            richPlainText: richPlain,
            hasRichPayload: true,
            ocrText: nil,
            fileURLString: nil,
            typeTitle: "HTML"
        )
        #expect(cardText.isEmpty, "Must not surface type name 'HTML' as content")
        #expect(ClipPreviewText.characterFooter(forPreviewText: cardText) == "Empty")
    }

    @Test
    func missionControlHeadingExtractsReadablePlain() {
        let html = #"<meta charset='utf-8'><h2 style="font-size: 28px; color: rgb(242, 243, 245)">Mission Control</h2>"#
        let richPlain = RichPlainText.extract(htmlText: html, rtfData: nil)
        #expect(richPlain == "Mission Control")

        let cardText = ClipPreviewText.resolve(
            plainText: "Mission Control",
            richPlainText: richPlain,
            hasRichPayload: true,
            ocrText: nil,
            fileURLString: nil,
            typeTitle: "HTML"
        )
        #expect(cardText == "Mission Control")
        #expect(cardText == richPlain)
    }

    @Test
    func emptyPlainWithoutRichFallsBackToTypeTitle() {
        let resolved = ClipPreviewText.resolve(
            plainText: "",
            richPlainText: nil,
            hasRichPayload: false,
            ocrText: nil,
            fileURLString: nil,
            typeTitle: "Text"
        )
        #expect(resolved == "Text")
    }

    @Test
    func ocrUsedWhenNoPlainOrRich() {
        let resolved = ClipPreviewText.resolve(
            plainText: "  ",
            richPlainText: nil,
            hasRichPayload: false,
            ocrText: "recognized line",
            fileURLString: nil,
            typeTitle: "Image"
        )
        #expect(resolved == "recognized line")
    }

    @Test
    func fileURLBasenameWhenNoText() {
        let resolved = ClipPreviewText.resolve(
            plainText: "",
            richPlainText: nil,
            hasRichPayload: false,
            ocrText: nil,
            fileURLString: "file:///tmp/notes/readme.md",
            typeTitle: "File"
        )
        #expect(resolved == "readme.md")
    }

    @Test
    func characterFooterSingularAndPlural() {
        #expect(ClipPreviewText.characterFooter(forPreviewText: "a") == "1 character")
        #expect(ClipPreviewText.characterFooter(forPreviewText: "ab") == "2 characters")
        #expect(ClipPreviewText.characterFooter(forPreviewText: "  ") == "Empty")
    }

    @Test
    func previewPlainMatchesCardForHtmlPayloadEndToEnd() {
        // Simulates what ClipItem.previewText + Space preview plain extraction share.
        let samples: [(plain: String, html: String, expect: String)] = [
            ("", #"<p>气泡箭头 caret</p>"#, "气泡箭头 caret"),
            ("", #"<span>0.7.187.231</span>"#, "0.7.187.231"),
            ("keep plain", #"<p>ignored</p>"#, "keep plain"),
        ]
        for sample in samples {
            let rich = RichPlainText.extract(htmlText: sample.html, rtfData: nil)
            let card = ClipPreviewText.resolve(
                plainText: sample.plain,
                richPlainText: sample.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rich : nil,
                hasRichPayload: true,
                ocrText: nil,
                fileURLString: nil,
                typeTitle: "HTML"
            )
            // Space preview always reads rich body when showing HTML editor; card must match when plain empty.
            if sample.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                #expect(card == rich)
                #expect(card == sample.expect)
            } else {
                #expect(card == sample.expect)
            }
        }
    }
}
