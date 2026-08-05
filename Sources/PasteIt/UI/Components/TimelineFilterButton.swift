import SwiftUI
import PasteItCore

/// Leading toolbar control: type filter. Inactive = icon only; active = one chip
/// with type · count and a clear affordance.
struct TimelineFilterButton: View {
    @ObservedObject var appState: AppState
    @State private var isPresented = false
    /// Filled after the popover paints (single-pass scan); nil while loading.
    @State private var filterCounts: [FilterCategory: Int]?
    @State private var countsTask: Task<Void, Never>?

    private var isActive: Bool { appState.selectedFilter != .all }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                appState.dismissPreview()
                isPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isActive
                          ? appState.selectedFilter.systemImage
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: isActive ? nil : 28, height: 28)

                    if isActive {
                        Text("\(appState.selectedFilter.title) · \(appState.visibleClips.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .padding(.leading, isActive ? 8 : 0)
                .padding(.trailing, isActive ? 4 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive {
                Button {
                    appState.setFilter(.all)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear type filter")
                .padding(.trailing, 4)
            }
        }
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .pasteItControlGlass()
        .help(isActive
              ? "Filter: \(appState.selectedFilter.title) · \(appState.visibleClips.count)"
              : "Filter by type")
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.15), value: appState.selectedFilter)
        .animation(.easeOut(duration: 0.15), value: appState.visibleClips.count)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            filterMenu
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                scheduleFilterCounts()
            } else {
                countsTask?.cancel()
                countsTask = nil
                filterCounts = nil
            }
        }
    }

    private var filterMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Filter by type")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(FilterCategory.menuItems) { category in
                Button {
                    appState.setFilter(category)
                    isPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.systemImage)
                            .frame(width: 16)
                        Text(category.title)
                        Spacer(minLength: 12)
                        Text(countLabel(for: category))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                        if appState.selectedFilter == category {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 12)
                        } else {
                            Color.clear.frame(width: 12)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if appState.selectedFilter == category {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 200)
    }

    private func countLabel(for category: FilterCategory) -> String {
        guard let filterCounts, let count = filterCounts[category] else { return "—" }
        return "\(count)"
    }

    /// Paint the menu first, then fill counts in one pass on the next turn.
    private func scheduleFilterCounts() {
        filterCounts = nil
        countsTask?.cancel()
        countsTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let counts = appState.countsMatchingAllFilters()
            guard !Task.isCancelled else { return }
            filterCounts = counts
        }
    }
}
