#!/usr/bin/env swift
// Draws the App Store product page header (3840 × 1646, 21:9) for each language:
// the app icon, name and slogan on warm paper, beside three phones showing the app.
// Usage: swift Scripts/generate_header.swift <repo-root>
// Reads AppStore/upload/iphone-6.9/<lang>/*.png (PNG copies of the screenshots) and writes
// AppStore/header/header-<lang>.jpg plus a PNG copy in AppStore/upload/header/.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let size = CGSize(width: 3840, height: 1646)

struct Locale_ {
    let code: String
    let slogan: String
    let formats: String
    let screens: [String] // left, center, right
}

let locales = [
    Locale_(code: "en", slogan: "Read. Highlight. Remember.", formats: "EPUB · FB2 · PDF · TXT",
            screens: ["3-quote", "2-reader", "4-focus"]),
    Locale_(code: "ru", slogan: "Читай. Выделяй. Запоминай.", formats: "EPUB · FB2 · PDF · TXT",
            screens: ["3-quote", "2-reader", "4-focus"]),
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let ink = color(26, 25, 28)
let muted = color(115, 112, 107)
let accent = color(199, 105, 59)

func serif(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) { return font }
    return NSFont(name: "Georgia", size: size) ?? base
}

func image(_ path: String) -> CGImage {
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: root.appendingPathComponent(path)))!
    return rep.cgImage!
}

/// A phone with its screen, centered at `center`, `height` tall, rotated by `angle` degrees.
func drawPhone(_ ctx: CGContext, screen: CGImage, center: CGPoint, height: CGFloat, angle: CGFloat) {
    let aspect = CGFloat(screen.width) / CGFloat(screen.height)
    let bezel = height * 0.018
    let body = CGSize(width: height * aspect + bezel * 2, height: height + bezel * 2)
    let corner = body.width * 0.155

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let frame = CGRect(x: -body.width / 2, y: -body.height / 2, width: body.width, height: body.height)

    // Soft, warm shadow.
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.035), blur: height * 0.09, color: color(60, 40, 20, 0.28).cgColor)
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(color(22, 22, 24).cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Hairline edge highlight.
    ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: bezel * 0.25, dy: bezel * 0.25),
                       cornerWidth: corner - bezel * 0.25, cornerHeight: corner - bezel * 0.25, transform: nil))
    ctx.setStrokeColor(color(90, 88, 86).cgColor)
    ctx.setLineWidth(bezel * 0.12)
    ctx.strokePath()

    // Screen.
    let screenRect = frame.insetBy(dx: bezel, dy: bezel)
    let screenCorner = corner - bezel
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: screenCorner, cornerHeight: screenCorner, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(screen, in: screenRect)
    ctx.restoreGState()
    ctx.restoreGState()
}

func render(_ locale: Locale_) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Warm paper with a soft light from the upper left.
    let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(251, 248, 242).cgColor, color(240, 232, 220).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(199, 105, 59, 0.10).cgColor, color(199, 105, 59, 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 2700, y: 820), startRadius: 0,
                           endCenter: CGPoint(x: 2700, y: 820), endRadius: 1100, options: [])

    // Text column, kept inside the central area so crops on smaller screens don't cut it.
    let left: CGFloat = 520
    let icon = image("Quolia/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    let iconRect = CGRect(x: left, y: 1010, width: 220, height: 220)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(60, 40, 20, 0.18).cgColor)
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 50, cornerHeight: 50, transform: nil))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 50, cornerHeight: 50, transform: nil))
    ctx.clip()
    ctx.draw(icon, in: iconRect)
    ctx.restoreGState()

    let name = NSAttributedString(string: "Quolia", attributes: [.font: serif(250, weight: .semibold), .foregroundColor: ink, .kern: -2])
    name.draw(at: CGPoint(x: left - 10, y: 690))

    let slogan = NSAttributedString(string: locale.slogan, attributes: [.font: serif(92, weight: .regular), .foregroundColor: ink])
    slogan.draw(at: CGPoint(x: left, y: 560))

    let rule = CGRect(x: left, y: 500, width: 120, height: 6)
    ctx.setFillColor(accent.cgColor)
    ctx.fill(rule)

    let formats = NSAttributedString(string: locale.formats, attributes: [
        .font: NSFont.systemFont(ofSize: 50, weight: .semibold), .foregroundColor: muted, .kern: 8,
    ])
    formats.draw(at: CGPoint(x: left, y: 400))

    // Three phones, the middle one in front.
    let screens = locale.screens.map { image("AppStore/upload/iphone-6.9/\(locale.code)/\($0).png") }
    drawPhone(ctx, screen: screens[0], center: CGPoint(x: 2330, y: 760), height: 1180, angle: 7)
    drawPhone(ctx, screen: screens[2], center: CGPoint(x: 3270, y: 760), height: 1180, angle: -7)
    drawPhone(ctx, screen: screens[1], center: CGPoint(x: 2800, y: 820), height: 1360, angle: 0)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// App Store artwork can't have an alpha channel.
func opaque(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
    let image = rep.cgImage!
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return NSBitmapImageRep(cgImage: context.makeImage()!)
}

for locale in locales {
    let rep = opaque(render(locale))
    for (folder, type, ext) in [("AppStore/header", NSBitmapImageRep.FileType.jpeg, "jpg"), ("AppStore/upload/header", .png, "png")] {
        let url = root.appendingPathComponent("\(folder)/header-\(locale.code).\(ext)")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! rep.representation(using: type, properties: type == .jpeg ? [.compressionFactor: 0.9] : [:])!.write(to: url)
        print("wrote \(folder)/header-\(locale.code).\(ext)")
    }
}
