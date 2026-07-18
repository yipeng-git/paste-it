import Foundation

extension Date {
    /// Static relative label for clip cards — computed once at render, never ticks.
    /// < 1 min → Just now; < 60 min → Nm ago; < 24 h → Nh ago; else → Nd ago.
    func pasteItCopiedLabel(relativeTo now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(self))
        if elapsed < 60 {
            return "Just now"
        }
        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = Int(elapsed / 3600)
        if hours < 24 {
            return "\(hours)h ago"
        }
        let days = max(1, Int(elapsed / 86400))
        return "\(days)d ago"
    }
}
