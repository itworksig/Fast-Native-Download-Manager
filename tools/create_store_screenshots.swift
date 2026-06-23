import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDir = root.appendingPathComponent("dist/chrome-store-screenshots", isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let icon = NSImage(contentsOf: root.appendingPathComponent("Browser Extension/chrome/icon-128.png"))
let canvas = NSSize(width: 1280, height: 800)

func color(_ hex: UInt32) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255
    let g = CGFloat((hex >> 8) & 0xff) / 255
    let b = CGFloat(hex & 0xff) / 255
    return NSColor(red: r, green: g, blue: b, alpha: 1)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: w, height: h)
}

func rounded(_ r: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}

func line(_ from: NSPoint, _ to: NSPoint, color: NSColor, width: CGFloat = 2) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color textColor: NSColor = color(0x172033), align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph
    ]
    NSString(string: value).draw(in: rect(x, y, w, h), withAttributes: attrs)
}

func pill(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
    rounded(rect(x, y, w, 34), radius: 17, fill: color(0xe8f2ff))
    text(value, x, y + 7, w, 20, size: 13, weight: .semibold, color: color(0x075cc6), align: .center)
}

func drawBrowserWindow(_ frame: NSRect, title: String) {
    rounded(frame, radius: 18, fill: .white, stroke: color(0xdfe4ee), width: 1)
    rounded(rect(frame.minX, frame.maxY - 58, frame.width, 58), radius: 18, fill: color(0xf7f8fb))
    line(NSPoint(x: frame.minX, y: frame.maxY - 58), NSPoint(x: frame.maxX, y: frame.maxY - 58), color: color(0xe5eaf3), width: 1)
    for (idx, c) in [0xff5f57, 0xffbd2e, 0x28c840].enumerated() {
        rounded(rect(frame.minX + 22 + CGFloat(idx) * 24, frame.maxY - 36, 12, 12), radius: 6, fill: color(UInt32(c)))
    }
    rounded(rect(frame.minX + 120, frame.maxY - 42, frame.width - 230, 26), radius: 13, fill: .white, stroke: color(0xe0e6f0), width: 1)
    text(title, frame.minX + 140, frame.maxY - 38, frame.width - 270, 18, size: 12, color: color(0x667085))
}

func drawDownloadCard(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ title: String, _ type: String, _ progress: CGFloat, _ status: String) {
    rounded(rect(x, y, w, 76), radius: 10, fill: .white, stroke: color(0xe1e7f0), width: 1)
    rounded(rect(x + 16, y + 24, 54, 28), radius: 7, fill: color(0xe8f2ff))
    text(type, x + 16, y + 30, 54, 16, size: 11, weight: .bold, color: color(0x075cc6), align: .center)
    text(title, x + 86, y + 43, w - 110, 18, size: 15, weight: .semibold)
    rounded(rect(x + 86, y + 22, w - 150, 8), radius: 4, fill: color(0xe9edf5))
    rounded(rect(x + 86, y + 22, (w - 150) * progress, 8), radius: 4, fill: color(0x0a73ff))
    text(status, x + w - 56, y + 18, 40, 18, size: 12, color: color(0x667085), align: .right)
}

func drawPopup(_ x: CGFloat, _ y: CGFloat) {
    rounded(rect(x, y, 360, 320), radius: 18, fill: color(0xf7f8fb), stroke: color(0xdfe4ee), width: 1)
    text("Downloads", x + 24, y + 265, 210, 34, size: 28, weight: .bold, color: color(0x172033))
    text("3 resources detected.", x + 24, y + 235, 220, 22, size: 16, color: color(0x5f6b7a))
    rounded(rect(x + 300, y + 250, 44, 44), radius: 12, fill: .white, stroke: color(0xd6deeb), width: 1)
    text("↻", x + 300, y + 256, 44, 32, size: 25, weight: .semibold, color: color(0x0a73ff), align: .center)
    drawDownloadCard(x + 24, y + 150, 312, "BigBuckBunny.mp4", "MP4", 0.84, "84%")
    drawDownloadCard(x + 24, y + 72, 312, "release-build.dmg", "DMG", 0.42, "42%")
    drawDownloadCard(x + 24, y - 6, 312, "playlist.m3u8", "M3U8", 0.62, "62%")
}

func drawAppWindow(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    rounded(rect(x, y, w, h), radius: 20, fill: .white, stroke: color(0xdfe4ee), width: 1)
    rounded(rect(x, y + h - 62, w, 62), radius: 20, fill: color(0xf7f8fb))
    text("Fast Native Download Manager", x + 28, y + h - 43, 360, 24, size: 17, weight: .semibold)
    rounded(rect(x + 28, y + h - 102, 96, 32), radius: 8, fill: color(0x0a73ff))
    text("Active", x + 28, y + h - 95, 96, 18, size: 13, weight: .semibold, color: .white, align: .center)
    text("File", x + 44, y + h - 144, 250, 18, size: 12, weight: .semibold, color: color(0x667085))
    text("Progress", x + w - 220, y + h - 144, 110, 18, size: 12, weight: .semibold, color: color(0x667085))
    drawDownloadCard(x + 28, y + h - 226, w - 56, "ubuntu-26.04-desktop.iso", "ISO", 0.76, "76%")
    drawDownloadCard(x + 28, y + h - 312, w - 56, "design-assets.zip", "ZIP", 0.52, "52%")
    drawDownloadCard(x + 28, y + h - 398, w - 56, "course-video.mp4", "MP4", 0.91, "91%")
}

func drawBase(_ title: String, _ subtitle: String) {
    color(0xf4f7fb).setFill()
    NSRect(origin: .zero, size: canvas).fill()
    rounded(rect(40, 40, 1200, 720), radius: 34, fill: color(0xffffff), stroke: color(0xe4e9f2), width: 1)
    if let icon {
        icon.draw(in: rect(82, 642, 78, 78))
    }
    text(title, 180, 655, 700, 52, size: 38, weight: .bold, color: color(0x172033))
    text(subtitle, 180, 618, 760, 30, size: 19, color: color(0x5f6b7a))
}

func save(_ name: String, draw: () -> Void) throws {
    let image = NSImage(size: canvas)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.94]) else {
        throw NSError(domain: "StoreScreenshots", code: 1)
    }
    try data.write(to: outputDir.appendingPathComponent(name))
}

try save("01-capture-downloads-1280x800.jpg") {
    drawBase("Capture Downloads From Chrome", "Send files, media, torrents, HLS, and DASH links to the native app.")
    drawBrowserWindow(rect(86, 112, 760, 470), title: "https://example.com/downloads")
    text("Download resources", 132, 500, 260, 28, size: 24, weight: .bold)
    drawDownloadCard(132, 394, 520, "macOS-installer.dmg", "DMG", 0.68, "68%")
    drawDownloadCard(132, 304, 520, "training-video.mp4", "MP4", 0.47, "47%")
    drawDownloadCard(132, 214, 520, "archive-pack.zip", "ZIP", 0.86, "86%")
    drawPopup(822, 170)
}

try save("02-right-click-handoff-1280x800.jpg") {
    drawBase("Right-Click Handoff", "Capture a link, image, video, audio source, selection, or current page.")
    drawBrowserWindow(rect(86, 118, 610, 450), title: "https://releases.example.com")
    rounded(rect(150, 372, 320, 48), radius: 10, fill: color(0xf0f7ff), stroke: color(0x9ac5ff), width: 1)
    text("Download with Fast Native Download Manager", 170, 386, 280, 18, size: 13, weight: .semibold, color: color(0x075cc6))
    line(NSPoint(x: 472, y: 396), NSPoint(x: 768, y: 396), color: color(0x0a73ff), width: 3)
    text("→", 742, 375, 60, 40, size: 36, weight: .bold, color: color(0x0a73ff), align: .center)
    drawAppWindow(770, 140, 420, 400)
}

try save("03-resource-grabber-1280x800.jpg") {
    drawBase("Find Downloadable Resources", "Scan the active tab and choose exactly what to send.")
    drawBrowserWindow(rect(86, 112, 700, 470), title: "https://video.example.com/watch")
    rounded(rect(138, 238, 596, 226), radius: 16, fill: color(0x101828))
    text("Video page", 166, 408, 300, 26, size: 23, weight: .bold, color: .white)
    text("The extension detects page resources and preserves cookies, Referer, Origin, and User-Agent hints.", 166, 358, 500, 52, size: 18, color: color(0xd0d5dd))
    pill("yt-dlp preset", 166, 304, 118)
    pill("ffmpeg", 300, 304, 88)
    pill("cookies", 404, 304, 88)
    drawPopup(830, 170)
}

print(outputDir.path)
