import SwiftUI
import PasteItCore

/// Leading toolbar control: opens an upward type-filter menu.
struct TimelineFilterButton: View {
    @ObservedObject var appState: AppState
    @State private var isPresented = false

    private var isActive: Bool { appState.selectedFilter != .all }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: -3, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.accentColor : .secondary)
        .pasteItControlGlass()
        .help(isActive ? "Filter: \(appState.selectedFilter.title)" : "Filter by type")
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
                        if appState.selectedFilter == category {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
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
        .frame(width: 180)
    }
}
