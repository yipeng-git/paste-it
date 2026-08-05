import AppKit

/// Diagonal C / V 3D keycaps for the menu-bar status item.
/// Matches KeyStats' MenuIcon feel: thick bottom/left rim, thin top/right,
/// recessed key face. Pressed = invert (fill) the key face.
@MainActor
final class MenuBarKeycapsView: NSView {
    enum Key {
        case c
        case v
    }

    private var cPressed = false
    private var vPressed = false
    private var pressResetWork: [Key: DispatchWorkItem] = [:]

    static let preferredSize = NSSize(width: 32, height: 22)

    override var intrinsicContentSize: NSSize { Self.preferredSize }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let keySize = NSSize(width: 16, height: 15)

        let cRect = NSRect(
            x: bounds.minX + 0.5,
            y: bounds.maxY - keySize.height - 0.5,
            width: keySize.width,
            height: keySize.height
        )
        let vRect = NSRect(
            x: bounds.maxX - keySize.width - 0.5,
            y: bounds.minY + 0.5,
            width: keySize.width,
            height: keySize.height
        )

        drawKeycap(in: vRect, label: "V", pressed: vPressed)
        drawKeycap(in: cRect, label: "C", pressed: cPressed)
    }

    private func drawKeycap(in outer: NSRect, label: String, pressed: Bool) {
        let ink = NSColor.labelColor
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Asymmetric inset → fatter SW rim, thin NE rim (KeyStats depth).
        let insetL: CGFloat = 3.4
        let insetB: CGFloat = 3.4
        let insetT: CGFloat = 1.2
        let insetR: CGFloat = 1.2
        let outerCorner = min(outer.width, outer.height) * 0.30

        let face = NSRect(
            x: outer.minX + insetL,
            y: outer.minY + insetB,
            width: max(1, outer.width - insetL - insetR),
            height: max(1, outer.height - insetB - insetT)
        )
        let faceCorner = min(face.width, face.height) * 0.30

        let outerPath = NSBezierPath(
            roundedRect: outer,
            xRadius: outerCorner,
            yRadius: outerCorner
        )
        let facePath = NSBezierPath(
            roundedRect: face,
            xRadius: faceCorner,
            yRadius: faceCorner
        )

        if pressed {
            // Invert key top: solid body + contrasting letter.
            ink.setFill()
            outerPath.fill()
        } else {
            // Rim only (even-odd punch of the face).
            let rim = NSBezierPath()
            rim.windingRule = .evenOdd
            rim.append(outerPath)
            rim.append(facePath)
            ink.setFill()
            rim.fill()
        }

        // Hairline on the thin NE edge so the silhouette stays complete.
        ink.withAlphaComponent(isDark ? 0.95 : 0.9).setStroke()
        outerPath.lineWidth = 1.0
        outerPath.lineJoinStyle = .round
        outerPath.stroke()

        // Letter centered on the face.
        let fontSize = max(7.0, min(face.width, face.height) * 0.72)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let textColor: NSColor
        if pressed {
            textColor = isDark ? .black : .controlBackgroundColor
        } else {
            textColor = ink
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: -0.6,
        ]
        let text = NSAttributedString(string: label, attributes: attrs)
        let size = text.size()
        text.draw(
            at: NSPoint(
                x: face.midX - size.width / 2,
                y: face.midY - size.height / 2 - 0.35
            )
        )
    }

    func flash(_ key: Key, duration: TimeInterval = 0.16) {
        pressResetWork[key]?.cancel()
        setPressed(true, for: key)
        let work = DispatchWorkItem { [weak self] in
            self?.setPressed(false, for: key)
        }
        pressResetWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func setPressed(_ pressed: Bool, for key: Key) {
        switch key {
        case .c: cPressed = pressed
        case .v: vPressed = pressed
        }
        needsDisplay = true
    }
}
