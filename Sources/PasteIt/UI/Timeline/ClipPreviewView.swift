import SwiftUI

struct ClipPreviewView: View {
    let item: ClipItem?
    let historyStore: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                HStack {
                    Label(item.primaryType.title, systemImage: item.primaryType.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if item.copyCount > 1 {
                        Text("×\(item.copyCount)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.title)
                    .font(.title3.bold())
                    .lineLimit(3)

                if let image = historyStore.thumbnailImage(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                ScrollView {
                    Text(item.previewText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)

                if let ocrText = item.ocrText, !ocrText.isEmpty {
                    DisclosureGroup("Image Text") {
                        Text(ocrText)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    metadataRow("Source", item.sourceAppName ?? "Unknown")
                    metadataRow("Copied", item.createdAt.formatted(date: .abbreviated, time: .standard))
                    metadataRow("Types", item.pasteboardTypes.prefix(3).joined(separator: ", "))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right")
            }
        }
        .padding(18)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .lineLimit(2)
        }
    }
}
