import AppKit
import ApplicationServices
import SwiftUI

/// Full Paste-style Stack surface: glass chrome, horizontal cards, direction control.
struct PasteStackView: View {
    @ObservedObject var stack: PasteStackController
    let historyStore: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack {
                if stack.items.isEmpty {
                    emptyState
                } else {
                    cardStrip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .pasteItPanelGlass()
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Paste Stack")
                    .font(.system(size: 14, weight: .bold))
                if stack.isCollecting {
                    Text("Collecting")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }
            }

            Spacer(minLength: 8)

            Text(stack.items.isEmpty ? "Empty" : "\(stack.items.count) items")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                stack.flipDirection()
            } label: {
                Label(
                    stack.direction == .oldestFirst ? "First in, first out" : "Last in, first out",
                    systemImage: "arrow.up.arrow.down"
                )
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .pasteItCapsuleGlass()
            .help("Change paste order")

            Button {
                stack.ensureAccessibilityIfNeeded()
                _ = stack.pasteNext()
            } label: {
                Text("Paste Next")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(stack.items.isEmpty)
            .opacity(stack.items.isEmpty ? 0.45 : 1)
            .pasteItCapsuleGlass()
            .help("⌥⌘V")

            Button {
                stack.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pasteItControlGlass()
            .help("Close Paste Stack (⇧⌘C)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Copy items to build your stack")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Then press ⌘V in any app to paste them in order")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            if !AXIsProcessTrusted() {
                Text("Grant Accessibility so ⌘V can advance the stack")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 12)
    }

    private var cardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(displayItems) { item in
                    stackCard(item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 8)
        }
    }

    /// Visual order matches paste order: next-to-paste is leftmost.
    private var displayItems: [ClipItem] {
        switch stack.direction {
        case .oldestFirst:
            return stack.items
        case .newestFirst:
            return Array(stack.items.reversed())
        }
    }

    private func stackCard(_ item: ClipItem) -> some View {
        let isNext = displayItems.first?.id == item.id
        return ClipCardView(
            item: item,
            historyStore: historyStore,
            isSelected: isNext,
            quickIndex: nil,
            query: ""
        )
        .frame(width: 200, height: 190)
        .overlay(alignment: .topLeading) {
            if isNext {
                Text("NEXT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .padding(10)
            }
        }
        .contextMenu {
            Button("Paste Now") {
                stack.promoteToNext(item)
                stack.ensureAccessibilityIfNeeded()
                _ = stack.pasteNext()
            }
            Button("Delete", role: .destructive) {
                withAnimation(.easeOut(duration: 0.15)) {
                    stack.remove(item)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < -60 {
                        withAnimation(.easeOut(duration: 0.15)) {
                            stack.remove(item)
                        }
                    }
                }
        )
    }
}
