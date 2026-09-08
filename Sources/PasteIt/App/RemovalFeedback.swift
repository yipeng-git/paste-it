import Combine
import Foundation

/// Transient feedback has its own observation boundary so its timer does not rebuild the timeline.
@MainActor
final class RemovalFeedback: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let removalID: UUID?
    }

    @Published private(set) var toast: Toast?
    private let displayDuration: Duration
    private var remaining: Duration = .zero
    private var startedAt: ContinuousClock.Instant?
    private var isHovered = false
    private var dismissalTask: Task<Void, Never>?

    init(displayDuration: Duration = .seconds(3)) {
        self.displayDuration = displayDuration
    }

    func show(_ message: String, removalID: UUID? = nil) {
        dismissalTask?.cancel()
        toast = Toast(message: message, removalID: removalID)
        remaining = displayDuration
        startedAt = nil
        scheduleDismissal()
    }

    func setHovered(_ hovered: Bool) {
        guard toast != nil, hovered != isHovered else { return }
        isHovered = hovered
        if hovered {
            dismissalTask?.cancel()
            if let startedAt {
                remaining = max(.zero, remaining - startedAt.duration(to: .now))
            }
            startedAt = nil
        } else {
            scheduleDismissal()
        }
    }

    func dismiss(id: UUID? = nil) {
        if let id, toast?.id != id { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        startedAt = nil
        isHovered = false
        toast = nil
    }

    private func scheduleDismissal() {
        guard !isHovered, let id = toast?.id else { return }
        let start = ContinuousClock.now
        startedAt = start
        let deadline = start.advanced(by: remaining)
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.dismiss(id: id)
        }
    }
}
