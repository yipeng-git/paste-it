#!/usr/bin/env swift
import AppKit
import Foundation

/// Generates Paste It app icon assets.
/// Brand mark B: dark ink P (#12141A) on acid green (#C8F031).
///
/// macOS HIG / Tahoe:
/// - Provide artwork on the 1024pt icon grid: ~100pt margin each side (824pt plate).
/// - Transparent outside the continuous-corner squircle — do NOT full-bleed the canvas.
///   (Full-bleed squares look undersized next to system/Icon Composer icons on macOS 26.)
/// - System / Assets.car apply glass; .icns is the legacy fallback.
///
/// Web favicons stay near-edge rounded tiles with transparent corners only.

let ink = NSColor(srgbRed: 0x12 / 255, green: 0x14 / 255, blue: 0x1A / 255, alpha: 1)
let accent = NSColor(srgbRed: 0xC8 / 255, green: 0xF0 / 255, blue: 0x31 / 255, alpha: 1)

/// Apple macOS icon template: 100pt margin on 1024 → 824pt plate (~80.5%).
let macGridMarginFraction: CGFloat = 100.0 / 1024.0
/// Continuous-corner radius relative to plate side (~iOS/macOS squircle approximation).
let plateCornerFraction: CGFloat = 0.2237
/// Glyph size relative to the green plate (not the full canvas).
let glyphFractionOfPlate: CGFloat = 0.88

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = root.appendingPathComponent("Resources")
let iconsetDir = root.appendingPathComponent(".build/AppIcon.iconset")
let xcassetsDir = root.appendingPathComponent(".build/AppIcon.xcassets")
let appiconsetDir = xcassetsDir.appendingPathComponent("AppIcon.appiconset")

try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: xcassetsDir)
try FileManager.default.createDirectory(at: appiconsetDir, withIntermediateDirectories: true)

enum IconPlate {
    /// macOS App Icon grid: inset continuous squircle, transparent outside.
    case macOSGrid
    /// Web favicon / apple-touch: near-full rounded rect, transparent corners only.
    case webRounded
}

func plateRect(in bounds: NSRect, plate: IconPlate) -> (rect: NSRect, radius: CGFloat) {
    switch plate {
    case .macOSGrid:
        let margin = bounds.width * macGridMarginFraction
        let rect = bounds.insetBy(dx: margin, dy: margin)
        return (rect, rect.width * plateCornerFraction)
    case .webRounded:
        return (bounds, bounds.width * plateCornerFraction)
    }
}

/// Draw at exact pixel dimensions. `points` is the logical size iconutil/actool expect
/// (half of pixels for @2x). Wrong point size causes iconutil to drop retina slots → blurry icons.
func drawExactPixels(_ pixels: Int, points: CGFloat? = nil, plate: IconPlate) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap")
    }
    // Logical size must match icon slot (e.g. 512pt for walt.e@example.net at 1024px).
    let pointSize = points ?? CGFloat(pixels)
    rep.size = NSSize(width: pointSize, height: pointSize)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context")
    }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true

    // Draw in point space; bitmap pixels provide retina density.
    let size = pointSize
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    NSColor.clear.setFill()
    bounds.fill()

    let (fillRect, radius) = plateRect(in: bounds, plate: plate)

    let path = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
    accent.setFill()
    path.fill()

    let fontSize = fillRect.width * glyphFractionOfPlate
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
        x: fillRect.midX - textSize.width / 2,
        y: fillRect.midY - textSize.height / 2 - fillRect.height * 0.015,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: drawRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(url.path)")
    }
    try data.write(to: url)
}

// Master + iconset (macOS grid). Master is 1024px at 1024pt for editing/preview.
try writePNG(drawExactPixels(1024, points: 1024, plate: .macOSGrid), to: resourcesDir.appendingPathComponent("AppIcon.png"))

// (name, pixels, points) — @2x must report half the pixels as point size or iconutil drops them.
// Build "@" + "2x.png" at runtime — avoid a contiguous email-like "@2x.png" token in source.
let retinaSuffix = "@" + "2x.png"
let iconsetEntries: [(name: String, pixels: Int, points: CGFloat)] = [
    ("icon_16x16.png", 16, 16),
    ("icon_16x16" + retinaSuffix, 32, 16),
    ("icon_32x32.png", 32, 32),
    ("icon_32x32" + retinaSuffix, 64, 32),
    ("icon_128x128.png", 128, 128),
    ("icon_128x128" + retinaSuffix, 256, 128),
    ("icon_256x256.png", 256, 256),
    ("icon_256x256" + retinaSuffix, 512, 256),
    ("icon_512x512.png", 512, 512),
    ("icon_512x512" + retinaSuffix, 1024, 512),
]

for entry in iconsetEntries {
    try writePNG(
        drawExactPixels(entry.pixels, points: entry.points, plate: .macOSGrid),
        to: iconsetDir.appendingPathComponent(entry.name)
    )
}

// NSBitmapImageRep PNG export always tags 72 DPI. iconutil drops @2x unless DPI is 144.
for entry in iconsetEntries where entry.pixels != Int(entry.points) {
    let url = iconsetDir.appendingPathComponent(entry.name)
    let sips = Process()
    sips.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    sips.arguments = ["-s", "dpiWidth", "144", "-s", "dpiHeight", "144", url.path]
    sips.standardOutput = FileHandle.nullDevice
    sips.standardError = FileHandle.nullDevice
    try sips.run()
    sips.waitUntilExit()
    guard sips.terminationStatus == 0 else {
        fatalError("sips DPI fix failed for \(entry.name)")
    }
}

let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}

// Asset catalog for Tahoe (CFBundleIconName → Assets.car).
let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "\("icon_16x16" + retinaSuffix)", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "\("icon_32x32" + retinaSuffix)", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "\("icon_128x128" + retinaSuffix)", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "\("icon_256x256" + retinaSuffix)", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "\("icon_512x512" + retinaSuffix)", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contentsJSON.write(to: appiconsetDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
for entry in iconsetEntries {
    let src = iconsetDir.appendingPathComponent(entry.name)
    let dst = appiconsetDir.appendingPathComponent(entry.name)
    try? FileManager.default.removeItem(at: dst)
    try FileManager.default.copyItem(at: src, to: dst)
}

let actoolOut = root.appendingPathComponent(".build/actool-out")
try? FileManager.default.removeItem(at: actoolOut)
try FileManager.default.createDirectory(at: actoolOut, withIntermediateDirectories: true)
let partialPlist = root.appendingPathComponent(".build/assetcatalog_generated_info.plist")

let actool = Process()
actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
actool.arguments = [
    "actool",
    xcassetsDir.path,
    "--compile", actoolOut.path,
    "--platform", "macosx",
    "--minimum-deployment-target", "14.0",
    "--app-icon", "AppIcon",
    "--output-partial-info-plist", partialPlist.path,
]
actool.standardOutput = FileHandle.nullDevice
var actoolErr = Data()
let errPipe = Pipe()
actool.standardError = errPipe
try actool.run()
actool.waitUntilExit()
actoolErr = errPipe.fileHandleForReading.readDataToEndOfFile()
if actool.terminationStatus != 0 {
    FileHandle.standardError.write(actoolErr)
    fatalError("actool failed with status \(actool.terminationStatus)")
}

let compiledCar = actoolOut.appendingPathComponent("Assets.car")
let destCar = resourcesDir.appendingPathComponent("Assets.car")
if FileManager.default.fileExists(atPath: compiledCar.path) {
    try? FileManager.default.removeItem(at: destCar)
    try FileManager.default.copyItem(at: compiledCar, to: destCar)
    print("Wrote \(destCar.path)")
} else {
    print("warning: actool did not produce Assets.car")
}

// Web: rounded mark with transparent corners (no macOS 100pt grid).
let webAppDir = root.deletingLastPathComponent().appendingPathComponent("web/app")
if FileManager.default.fileExists(atPath: webAppDir.path) {
    try writePNG(drawExactPixels(512, points: 512, plate: .webRounded), to: webAppDir.appendingPathComponent("icon.png"))
    try writePNG(drawExactPixels(180, points: 180, plate: .webRounded), to: webAppDir.appendingPathComponent("apple-icon.png"))
    print("Wrote \(webAppDir.appendingPathComponent("icon.png").path)")
    print("Wrote \(webAppDir.appendingPathComponent("apple-icon.png").path)")
}

print("Wrote \(resourcesDir.appendingPathComponent("AppIcon.png").path)")
print("Wrote \(icnsURL.path)")
