import SwiftUI

/// Read-only timeline chrome for Agent API ephemeral screenshot sessions.
struct EphemeralTimelineView: View {
    @ObservedObject var historyStore: HistoryStore
    let query: String
    let selectedType: ClipType?
    let selectedIndex: Int

    private let searchService = SearchService()

    private var visibleClips: [ClipItem] {
        searchService.search(
            clips: historyStore.clips,
            query: query,
            selectedType: selectedType,
            sourceApp: nil,
            pinboardID: nil,
            foldedHaystack: { [historyStore] item in
                historyStore.foldedSearchText(for: item)
            }
        )
    }

    var body: some View {
        let clips = visibleClips
        let selectedID = clips.indices.contains(selectedIndex) ? clips[selectedIndex].id : clips.first?.id

        VStack(spacing: 0) {
            toolbar
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(clips.prefix(30).enumerated()), id: \.element.id) { index, item in
                            ClipCardView(
                                item: item,
                                historyStore: historyStore,
                                isSelected: item.id == selectedID,
                                quickIndex: index < 9 ? index + 1 : nil,
                                query: query
                            )
                            .frame(width: 238, height: 232)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .padding(.top, 8)
                }

                if clips.isEmpty {
                    Text(query.isEmpty ? "No clips" : "No matching clips")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ClearHostingBackground())
        .pasteItPanelGlass()
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(TimelineTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if tab == .timeline {
                                Capsule().fill(Color.primary.opacity(0.12))
                            }
                        }
                        .foregroundStyle(tab == .timeline ? .primary : .secondary)
                }
            }
            .padding(3)
            .pasteItCapsuleGlass()

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? "Search (⌘F)" : query)
                    .foregroundStyle(query.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 260, height: 30)
            .pasteItControlGlass()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}
