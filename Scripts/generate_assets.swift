#!/usr/bin/env swift
// Generates the app icon (light + dark) and the sample book cover.
// Usage: swift Scripts/generate_assets.swift <repo-root>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

func serifFont(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return NSFont(name: "Georgia", size: size) ?? base
}

func render(size: CGSize, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: CGRect, kern: CGFloat = 0) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
    string.draw(with: CGRect(x: rect.minX, y: rect.midY - bounds.height / 2, width: rect.width, height: bounds.height),
                options: [.usesLineFragmentOrigin])
}

// MARK: - App icon

func icon(dark: Bool) -> NSBitmapImageRep {
    let size = CGSize(width: 1024, height: 1024)
    return render(size: size) { ctx in
        let colors = dark
            ? [color(30, 28, 27), color(14, 13, 13)]
            : [color(252, 249, 242), color(240, 232, 218)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

        // Bookmark ribbon
        let ribbon = CGMutablePath()
        let x: CGFloat = 640, w: CGFloat = 118, top: CGFloat = 1024, bottom: CGFloat = 640
        ribbon.move(to: CGPoint(x: x, y: top))
        ribbon.addLine(to: CGPoint(x: x + w, y: top))
        ribbon.addLine(to: CGPoint(x: x + w, y: bottom))
        ribbon.addLine(to: CGPoint(x: x + w / 2, y: bottom + 52))
        ribbon.addLine(to: CGPoint(x: x, y: bottom))
        ribbon.closeSubpath()
        ctx.addPath(ribbon)
        ctx.setFillColor(dark ? color(236, 147, 96) : color(200, 104, 58))
        ctx.fillPath()

        // Q
        let ink = dark ? NSColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1) : NSColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 1)
        drawCentered("Q", font: serifFont(660, weight: .medium), color: ink, in: CGRect(x: 60, y: 40, width: 904, height: 904))
    }
}

// MARK: - Sample cover

func cover() -> NSBitmapImageRep {
    let size = CGSize(width: 1200, height: 1800)
    return render(size: size) { ctx in
        ctx.setFillColor(color(244, 238, 226))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(color(200, 104, 58))
        ctx.fill(CGRect(x: 140, y: 1270, width: 120, height: 8))
        let ink = NSColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        let title = NSAttributedString(string: "On Reading\nSlowly", attributes: [
            .font: serifFont(150, weight: .semibold), .foregroundColor: ink, .paragraphStyle: style,
        ])
        title.draw(with: CGRect(x: 140, y: 880, width: 960, height: 360), options: [.usesLineFragmentOrigin])
        let subtitle = NSAttributedString(string: "Five short essays on attention,\nmemory and the reading life", attributes: [
            .font: serifFont(48, weight: .regular), .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: style,
        ])
        subtitle.draw(with: CGRect(x: 140, y: 700, width: 960, height: 140), options: [.usesLineFragmentOrigin])
        let author = NSAttributedString(string: "QUOLIA EDITIONS", attributes: [
            .font: NSFont.systemFont(ofSize: 36, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.75), .kern: 8,
        ])
        author.draw(at: CGPoint(x: 140, y: 170))
    }
}

func write(_ rep: NSBitmapImageRep, _ path: String, type: NSBitmapImageRep.FileType) {
    let url = root.appendingPathComponent(path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = rep.representation(using: type, properties: type == .jpeg ? [.compressionFactor: 0.88] : [:])!
    try! data.write(to: url)
    print("wrote \(path)")
}

write(icon(dark: false), "Quolia/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png", type: .png)
write(icon(dark: true), "Quolia/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png", type: .png)
write(cover(), "Scripts/SampleBook/OEBPS/images/cover.jpg", type: .jpeg)
