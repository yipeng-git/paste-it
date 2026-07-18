import AppKit
import ObjectiveC

/// macOS Tahoe (26) auto-injects SF Symbol action images on menu items
/// (gear for Preferences/Settings, etc.). Clearing `image` in `menuWillOpen`
/// is too late — AppKit re-applies them when drawing.
///
/// Approach (NetNewsWire / Rogue Amoeba pattern):
/// 1. Opt this app out of automatic action images via UserDefaults.
/// 2. Swizzle `NSMenuItem.image` so system-injected icons never show unless
///    we explicitly opt an item in via `pasteItShowsMenuImage`.
enum MenuIconPolicy {
    /// Call once at launch, before any menu is shown.
    static func disableSystemInjectedIcons() {
        UserDefaults.standard.register(defaults: ["NSMenuEnableActionImages": false])
        // App-domain write so we win even if a global default is YES.
        UserDefaults.standard.set(false, forKey: "NSMenuEnableActionImages")

        guard #available(macOS 26.0, *) else { return }
        NSMenuItem.pasteIt_installImageSwizzleIfNeeded()
    }
}

extension NSMenuItem {
    // Swizzle install state is mutated once on the main thread at launch.
    nonisolated(unsafe) private static var didSwizzle = false
    nonisolated(unsafe) private static var originalImageIMP: IMP?
    nonisolated(unsafe) private static var showsMenuImageKey: UInt8 = 0

    /// Set to `true` only for items where we intentionally provide an icon.
    var pasteItShowsMenuImage: Bool {
        get {
            (objc_getAssociatedObject(self, &Self.showsMenuImageKey) as? NSNumber)?.boolValue ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.showsMenuImageKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    fileprivate static func pasteIt_installImageSwizzleIfNeeded() {
        guard !didSwizzle else { return }
        guard
            let original = class_getInstanceMethod(NSMenuItem.self, #selector(getter: NSMenuItem.image)),
            let swizzled = class_getInstanceMethod(NSMenuItem.self, #selector(pasteIt_swizzledImage))
        else {
            return
        }
        originalImageIMP = method_getImplementation(original)
        method_exchangeImplementations(original, swizzled)
        didSwizzle = true
    }

    @objc private func pasteIt_swizzledImage() -> NSImage? {
        // Keep empty-title / toolbar representations working; hide everything else
        // unless we explicitly opted in (this app never sets menu icons).
        if pasteItShowsMenuImage || title.isEmpty || menu == nil {
            return pasteIt_invokeOriginalImageGetter()
        }
        return nil
    }

    private func pasteIt_invokeOriginalImageGetter() -> NSImage? {
        guard let imp = Self.originalImageIMP else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSImage?
        let fn = unsafeBitCast(imp, to: Getter.self)
        // After exchange, the original implementation is still the stored IMP.
        return fn(self, #selector(getter: NSMenuItem.image))
    }
}
