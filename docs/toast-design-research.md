# Floating toast design research

Research date: 2026-09-08. Scope: the removal toast and its Undo action; the main timeline layout stays unchanged.

## Findings and evidence

| Reference | Verified behavior or implementation | What to borrow |
| --- | --- | --- |
| [Raycast Toast](https://developers.raycast.com/api-reference/feedback/toast) and [HUD](https://developers.raycast.com/api-reference/feedback/hud) | Toasts support primary/secondary action callbacks, including undo, with actions available on hover. The separate HUD displays a compact result after the main window closes. These public extension APIs do not reveal Raycast's native material implementation. | A concise result with a real action. Keep our Undo visible immediately because our toast lasts only three seconds. |
| [Paste 6](https://pasteapp.io/blog/paste-in-liquid-glass) | The vendor describes a native Liquid Glass redesign with translucent floating windows and rounded content. It does not publish a toast-specific component or glass variant. The linked image asset could not be retrieved during this review. | Use the same lightweight floating-surface direction; do not claim an exact copy of Paste's toast. |
| [CleanShot Quick Access Overlay](https://cleanshot.com/features) | The official feature page describes a transient screenshot overlay with copy/save/annotate actions, positioning, resizing, and auto-close. This is an action overlay, not evidence of a Liquid Glass capsule. | Give the action an identifiable interactive area; avoid treating the whole notification as one button. |
| [TinyRecorder recording HUD source](https://github.com/Aaru1801/TinyTask-macOS/blob/main/Sources/TinyRecorder/RecordingHUD.swift) | The open-source HUD embeds an NSHostingView in NSGlassEffectView inside a transparent, nonactivating NSPanel. Older macOS uses NSVisualEffectView with behind-window blending. It adds its own dark overlay and shadow. This is an implementation reference, not evidence of mainstream adoption. | Native AppKit glass for a desktop floating surface. Do not copy its large recording layout, dark overlay, or extra shadow. |
| [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) and [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) | Regular glass adapts to its backdrop for legibility; Clear is intended for media-rich backgrounds with bright foreground content and appropriate dimming. Glass includes adaptive depth and shadows. The public AppKit API exposes style, corner radius, tint, and a content view. | One native glass surface, no hand-painted opaque fill or additional window shadow. Judge the rendered result, not the presence of an API call. |

There is no verified universal “mainstream Liquid Glass toast” recipe in these sources. The design combines an established actionable-notification pattern with Apple's native material. Closed-source app internals and exact transparency values remain unknown.

## Implementation decision

- Keep the content-sized, 44-point capsule and the 56-point rounded rectangle for long messages. Position the separate non-key window 12 points above the timeline.
- Use AppKit NSGlassEffectView for the desktop-facing material on macOS 26+, with a behind-window visual-effect fallback. The regular variant was rendered in a signed build and still appeared as a flat gray capsule on the current background. Use Clear glass with bright text and a localized 55% black dimming layer for the requested transparency. This is a product-specific tradeoff: arbitrary desktop content is broader than Apple’s recommended media-rich use case, so contrast on bright and busy backgrounds is checked using a separate synthetic backdrop window. Dimming applies only inside the toast, so background color still shows through. A dark material appearance keeps the system accessibility fallback compatible with white text. Do not simulate transparency by lowering the opacity of the whole window and its text.
- Remove the explicit NSPanel shadow. The system glass may still produce subtle adaptive depth; zero shadow is not a defining property of Liquid Glass.
- Make the glass background ignore hit testing. On macOS 15+, explicitly allow the Undo button to receive first-click events in the non-key panel; macOS 14 retains the native borderless button style. Give Undo a 32-point-high target with padding inside the Button label. A faint action fill makes Undo identifiable before hover. Hover brightens the highlight; pressing strengthens it and briefly compresses the action. Reduce Motion disables compression/animation. Increased Contrast adds an action outline on hover/press.
- Keep the existing undo callback, identity checks, three-second display duration, hover pause, and 30-second recovery window. Successful Undo restores the item and replaces the message with the restoration result.

## Verification

Native rendering, signed installation, and interaction results are recorded in [the product experience roadmap](product-experience-roadmap.md#implementation-record). Screenshots alone cannot prove pointer delivery or hover behavior. The regression test exercises the displayed view's callback against a temporary history store and checks restoration, child-window placement, focus, and absence of an additional window shadow.
