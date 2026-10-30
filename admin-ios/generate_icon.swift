import AppKit
import Foundation

// Source-controlled, deterministic 1024x1024 black & white Nightwell Admin icon.
// This build-time vector renderer avoids binary blobs in Git history.
let size = 1024
let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let context = NSGraphicsContext(bitmapImageRep: canvas)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
let full = NSRect(x: 0, y: 0, width: size, height: size)
NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
full.fill()

// Soft concentric framing, subtly separated from the pitch-black base.
for index in 0..<5 {
    let inset = CGFloat(44 + index * 18)
    let alpha = CGFloat(0.17) / CGFloat(index + 1)
    let path = NSBezierPath(roundedRect: full.insetBy(dx: inset, dy: inset),
                            xRadius: 175, yRadius: 175)
    path.lineWidth = index == 0 ? 4 : 2
    NSColor(calibratedWhite: 0.8, alpha: alpha).setStroke()
    path.stroke()
}

// The Nightwell N: original simple geometric white monogram.
let n = NSBezierPath()
n.move(to: NSPoint(x: 290, y: 302))
n.line(to: NSPoint(x: 290, y: 716))
n.curve(to: NSPoint(x: 736, y: 306),
        controlPoint1: NSPoint(x: 460, y: 721),
        controlPoint2: NSPoint(x: 567, y: 301))
n.line(to: NSPoint(x: 736, y: 716))
n.lineCapStyle = .round
n.lineJoinStyle = .round
n.lineWidth = 65
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 1, alpha: 0.35)
shadow.shadowBlurRadius = 31
shadow.shadowOffset = NSSize(width: 0, height: 0)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
n.stroke()
NSGraphicsContext.restoreGraphicsState()

// A restrained admin control indicator below the monogram.
let underline = NSBezierPath()
underline.move(to: NSPoint(x: 425, y: 200))
underline.line(to: NSPoint(x: 599, y: 200))
underline.lineWidth = 12
underline.lineCapStyle = .round
NSColor(calibratedWhite: 0.65, alpha: 0.9).setStroke()
underline.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let iconFolder = URL(fileURLWithPath: "admin-ios/NightwellAdmin/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconFolder, withIntermediateDirectories: true)
let png = canvas.representation(using: .png, properties: [:])!
try png.write(to: iconFolder.appendingPathComponent("AppIcon.png"), options: .atomic)
let contents: [String: Any] = [
    "images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": ["author": "xcode", "version": 1]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconFolder.appendingPathComponent("Contents.json"), options: .atomic)
print("Nightwell Admin icon created: 1024x1024")
