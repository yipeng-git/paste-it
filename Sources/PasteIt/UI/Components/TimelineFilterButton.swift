import SwiftUI
import PasteItCore

/// Leading toolbar control: type filter. Inactive = icon only; active = one chip
/// with type · count and a clear affordance.
struct TimelineFilterButton: View {
    @ObservedObject var appState: AppState
    @State private var isPresented = false

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
                        Text("\(appState.countMatching(filter: category))")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
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
}
