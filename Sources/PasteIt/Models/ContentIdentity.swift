import Foundation

enum ContentIdentity {
    static func duplicateKey(
        primaryType: ClipType,
        plainText: String,
        fileURLString: String?,
        ocrText: String?,
        contentHash: String
    ) -> String {
        if let normalizedText = normalize(plainText) {
            return "text:\(normalizedText)"
        }

        if let normalizedURL = normalize(fileURLString) {
            return "url:\(normalizedURL)"
        }

        if primaryType == .image {
            return "image:\(contentHash)"
        }

        if let normalizedOCRText = normalize(ocrText) {
            return "ocr:\(normalizedOCRText)"
        }

        return "hash:\(contentHash)"
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }
}

extension CapturedClip {
    var duplicateContentKey: String {
        ContentIdentity.duplicateKey(
            primaryType: primaryType,
            plainText: plainText,
            fileURLString: fileURLString,
            ocrText: ocrText,
            contentHash: contentHash
        )
    }
}

extension ClipItem {
    var duplicateContentKey: String {
        ContentIdentity.duplicateKey(
            primaryType: primaryType,
            plainText: plainText,
            fileURLString: fileURLString,
            ocrText: ocrText,
            contentHash: contentHash
        )
    }
}
