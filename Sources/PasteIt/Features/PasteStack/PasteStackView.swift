import AppKit
import ApplicationServices
import PasteItCore
import SwiftUI

/// Right-rail Stack: compact queue rows, visually distinct from the bottom timeline.
struct PasteStackView: View {
    @ObservedObject var stack: PasteStackController
    let historyStore: HistoryStore

    private static let gripHeight = PasteStackPanelLayout.gripHeight

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            ZStack {
                if stack.items.isEmpty {
                    emptyState
                } else {
                    cardStrip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            resizeGrip
                .frame(height: Self.gripHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pasteItPanelGlass()
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("stack.title", default: "Stack"))
                        .font(.system(size: 13, weight: .bold))
                    if stack.isCollecting {
                        Text(L10n.tr("stack.collecting", default: "Collecting"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                pasteItStatusCapsule(tint: .green)
                            }
                    }
                }
                .allowsHitTesting(false)

                Spacer(minLength: 4)
                Button {
                    stack.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pasteItControlGlass()
                .help(L10n.tr("stack.closeHelp", default: "Close Paste Stack (⇧⌘C)"))
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(stack.items.isEmpty ? L10n.tr("clipType.empty", default: "Empty") : "\(stack.items.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(L10n.tr("stack.pasteNext", default: "⌘V pastes next"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .allowsHitTesting(false)

                Spacer(minLength: 4)
                Button {
                    stack.flipDirection()
                } label: {
                    Image(systemName: stack.direction.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pasteItControlGlass()
                .help(stack.direction.toggleHelp)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            PasteStackWindowDragArea()
        }
    }

    private var emptyState: some View {
        ZStack {
            PasteStackWindowDragArea()
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("stack.emptyTitle", default: "Copy to fill the stack"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(L10n.tr("stack.emptySubtitle", default: "Then ⌘V in any app"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                if !AXIsProcessTrusted() {
                    Text(L10n.tr("stack.accessibilityHint", default: "Grant Accessibility so ⌘V can advance the stack"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .allowsHitTesting(false)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var cardStrip: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: PasteStackPanelLayout.rowSpacing) {
                ForEach(displayItems) { item in
                    stackRow(item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .padding(.top, 2)
        }
    }

    private var resizeGrip: some View {
        Capsule()
            .fill(Color.primary.opacity(0.28))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .help(L10n.tr("stack.resizeHelp", default: "Drag to resize height"))
    }

    /// Visual order matches paste order: next-to-paste is at the top.
    private var displayItems: [ClipItem] {
        switch stack.direction {
        case .oldestFirst:
            return stack.items
        case .newestFirst:
            return Array(stack.items.reversed())
        }
    }

    private func stackRow(_ item: ClipItem) -> some View {
        let isNext = displayItems.first?.id == item.id
        return PasteStackClipRow(
            item: item,
            historyStore: historyStore,
            isNext: isNext
        )
        .contextMenu {
            Button(L10n.tr("stack.moveToNext", default: "Move to Next")) {
                stack.promoteToNext(item)
            }
            Button(L10n.tr("stack.delete", default: "Delete"), role: .destructive) {
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

/// Transparent hit target so the header / empty state can drag the panel.
struct PasteStackWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> PasteStackWindowDragView {
        PasteStackWindowDragView()
    }

    func updateNSView(_ nsView: PasteStackWindowDragView, context: Context) {}
}

final class PasteStackWindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
