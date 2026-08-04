#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates Paste It Liquid Glass app icon assets via Icon Composer.
/// Brand mark B: dark ink P (#12141A) on acid green (#C8F031).
///
/// Pipeline (same as Magic Remote):
/// 1. Rasterize a transparent P glyph (no baked squircle / shadows / highlights)
/// 2. `icon-composer` → `design/AppIcon.icon` with glass + light/dark fills
/// 3. `actool` compiles `.icon` → `Resources/Assets.car` + `AppIcon.icns`
/// 4. Marketing flat PNG → `Resources/AppIcon.png` (+ optional web favicons)
///
/// Requires: Xcode (ictool / actool), Node (`npx icon-composer-mcp`).

let ink = NSColor(srgbRed: 0x12 / 255, green: 0x14 / 255, blue: 0x1A / 255, alpha: 1)
let accentHex = "#C8F031"
let darkAccentHex = "#8FB01F"
/// Glyph size relative to the full 1024 canvas (Icon Composer applies system mask).
let glyphFractionOfCanvas: CGFloat = 0.62

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let designDir = root.appendingPathComponent("design")
let layersDir = designDir.appendingPathComponent("layers")
let resourcesDir = root.appendingPathComponent("Resources")
let iconBundle = designDir.appendingPathComponent("AppIcon.icon")
let glyphURL = layersDir.appendingPathComponent("glyph-p.png")
let actoolOut = root.appendingPathComponent(".build/actool-icon-out")

try FileManager.default.createDirectory(at: layersDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

func run(_ executable: String, _ arguments: [String], cwd: URL? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let cwd {
        process.currentDirectoryURL = cwd
    }
    let err = Pipe()
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let data = err.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            FileHandle.standardError.write(Data(text.utf8))
        }
        fatalError("\(executable) failed with status \(process.terminationStatus)")
    }
}

func which(_ name: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n").first
        .map(String.init)
}

// MARK: - 1. Glyph (transparent; glass comes from Icon Composer)

func renderGlyph(to url: URL) throws {
    let size = 1024
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create glyph bitmap")
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context")
    }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let fontSize = CGFloat(size) * glyphFractionOfCanvas
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ink,
        .paragraphStyle: paragraph,
        .kern: -fontSize * 0.02,
    ]
    let text = NSAttributedString(string: "P", attributes: attrs)
    let textSize = text.size()
    let drawRect = NSRect(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2 - CGFloat(size) * 0.012,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: drawRect)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode glyph PNG")
    }
    try png.write(to: url)
    print("Wrote \(url.path)")
}

try renderGlyph(to: glyphURL)

// MARK: - 2. Icon Composer → .icon

guard let npx = which("npx") else {
    fatalError("npx not found — install Node.js to run icon-composer-mcp")
}

try? FileManager.default.removeItem(at: iconBundle)

try run(npx, [
    "-y", "--package=icon-composer-mcp", "icon-composer", "create",
    glyphURL.path,
    designDir.path,
    "--bundle-name", "AppIcon",
    "--bg-color", accentHex,
    "--dark-bg-color", darkAccentHex,
    "--glyph-scale", "1",
    "--no-split-layers",
    "--specular",
    "--shadow-kind", "layer-color",
    "--shadow-opacity", "0.45",
], cwd: root)

try run(npx, [
    "-y", "--package=icon-composer-mcp", "icon-composer", "glass",
    iconBundle.path,
    "--group-index", "0",
    "--specular",
    "--shadow-kind", "layer-color",
    "--shadow-opacity", "0.5",
    "--blur-material", "0",
    "--no-translucency-enabled",
    "--lighting", "individual",
], cwd: root)

let liquidPreview = designDir.appendingPathComponent("app-icon-liquid-glass.png")
let marketingPNG = designDir.appendingPathComponent("app-icon-marketing.png")

try run(npx, [
    "-y", "--package=icon-composer-mcp", "icon-composer", "render",
    iconBundle.path, liquidPreview.path,
], cwd: root)

try run(npx, [
    "-y", "--package=icon-composer-mcp", "icon-composer", "export-marketing",
    iconBundle.path, marketingPNG.path,
], cwd: root)

print("Wrote \(iconBundle.path)")
print("Wrote \(liquidPreview.path)")
print("Wrote \(marketingPNG.path)")

// MARK: - 3. actool → Assets.car + AppIcon.icns

try? FileManager.default.removeItem(at: actoolOut)
try FileManager.default.createDirectory(at: actoolOut, withIntermediateDirectories: true)
let partialPlist = root.appendingPathComponent(".build/assetcatalog_generated_info.plist")

try run("/usr/bin/xcrun", [
    "actool",
    iconBundle.path,
    "--compile", actoolOut.path,
    "--platform", "macosx",
    "--minimum-deployment-target", "14.0",
    "--app-icon", "AppIcon",
    "--output-partial-info-plist", partialPlist.path,
])

func install(_ name: String) throws {
    let src = actoolOut.appendingPathComponent(name)
    let dst = resourcesDir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: src.path) else {
        fatalError("actool did not produce \(name)")
    }
    try? FileManager.default.removeItem(at: dst)
    try FileManager.default.copyItem(at: src, to: dst)
    print("Wrote \(dst.path)")
}

try install("Assets.car")
try install("AppIcon.icns")

let appIconPNG = resourcesDir.appendingPathComponent("AppIcon.png")
try? FileManager.default.removeItem(at: appIconPNG)
try FileManager.default.copyItem(at: marketingPNG, to: appIconPNG)
print("Wrote \(appIconPNG.path)")

// MARK: - 4. Optional web favicons (sibling paste-it-web)

let webAppDir = root.deletingLastPathComponent().appendingPathComponent("paste-it-web/app")
if FileManager.default.fileExists(atPath: webAppDir.path) {
    func scaleMarketing(to pixels: Int, dest: URL) throws {
        guard let src = NSImage(contentsOf: marketingPNG) else {
            fatalError("Failed to load marketing PNG")
        }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("Failed to create web icon bitmap")
        }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Near-full rounded tile for web (transparent corners only).
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor.clear.setFill()
        bounds.fill()
        let radius = bounds.width * 0.2237
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        path.addClip()
        src.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to encode web icon")
        }
        try png.write(to: dest)
        print("Wrote \(dest.path)")
    }
    try scaleMarketing(to: 512, dest: webAppDir.appendingPathComponent("icon.png"))
    try scaleMarketing(to: 180, dest: webAppDir.appendingPathComponent("apple-icon.png"))
}
