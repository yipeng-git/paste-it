import AppKit

/// Diagonal C / V 3D keycaps rendered as a menu-bar template image.
/// Matches KeyStats' MenuIcon feel: thick bottom/left rim, thin top/right,
/// recessed key face. Pressed = invert (fill) the key face with a punched letter.
///
/// Uses `isTemplate = true` so the system tints the silhouette like other apps;
/// hold/release swaps the template image between hollow and solid keycaps.
@MainActor
final class MenuBarKeycapsIcon {
    enum Key {
        case c
        case v
    }

    static let preferredSize = NSSize(width: 32, height: 22)

    private var cPressed = false
    private var vPressed = false

    /// Called whenever the template image should be reapplied to the status button.
    var onImageChange: ((NSImage) -> Void)?

    func currentImage() -> NSImage {
        Self.makeTemplateImage(cPressed: cPressed, vPressed: vPressed)
    }

    func publish() {
        onImageChange?(currentImage())
    }

    /// Hold → solid; release → hollow. No timed flash.
    func setPressed(_ pressed: Bool, for key: Key) {
        switch key {
        case .c:
            guard cPressed != pressed else { return }
            cPressed = pressed
        case .v:
            guard vPressed != pressed else { return }
            vPressed = pressed
        }
        publish()
    }

    static func makeTemplateImage(cPressed: Bool, vPressed: Bool) -> NSImage {
        let size = preferredSize
        let image = NSImage(size: size, flipped: false) { bounds in
            drawKeycaps(in: bounds, cPressed: cPressed, vPressed: vPressed)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawKeycaps(in bounds: NSRect, cPressed: Bool, vPressed: Bool) {
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

        // V under C so the diagonal stack reads clearly.
        drawKeycap(in: vRect, label: "V", pressed: vPressed)
        drawKeycap(in: cRect, label: "C", pressed: cPressed)
    }

    private static func drawKeycap(in outer: NSRect, label: String, pressed: Bool) {
        // Template images: only alpha matters; draw opaque black, punch holes for invert.
        let ink = NSColor.black

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
            // Solid body; letter punched out so the menu bar shows through (invert).
            ink.setFill()
            outerPath.fill()
            punchLetter(label, in: face)
        } else {
            // Rim only (even-odd punch of the face).
            let rim = NSBezierPath()
            rim.windingRule = .evenOdd
            rim.append(outerPath)
            rim.append(facePath)
            ink.setFill()
            rim.fill()

            // Hairline on the thin NE edge so the silhouette stays complete.
            ink.withAlphaComponent(0.95).setStroke()
            outerPath.lineWidth = 1.0
            outerPath.lineJoinStyle = .round
            outerPath.stroke()

            drawLetter(label, in: face, color: ink)
        }
    }

    private static func letterAttrs(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
            .kern: -0.6,
        ]
    }

    private static func letterFontSize(for face: NSRect) -> CGFloat {
        max(7.0, min(face.width, face.height) * 0.72)
    }

    private static func drawLetter(_ label: String, in face: NSRect, color: NSColor) {
        let attrs = letterAttrs(fontSize: letterFontSize(for: face), color: color)
        let text = NSAttributedString(string: label, attributes: attrs)
        let size = text.size()
        text.draw(
            at: NSPoint(
                x: face.midX - size.width / 2,
                y: face.midY - size.height / 2 - 0.35
            )
        )
    }

    /// Clears the letter glyph so pressed keys read as inverted silhouettes.
    private static func punchLetter(_ label: String, in face: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            drawLetter(label, in: face, color: .white)
            return
        }
        context.saveGState()
        context.setBlendMode(.destinationOut)
        drawLetter(label, in: face, color: .black)
        context.restoreGState()
    }
}
