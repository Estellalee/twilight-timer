import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
let icnsOutput = CommandLine.arguments.dropFirst(2).first ?? "AppIcon.icns"
let fileManager = FileManager.default
try? fileManager.removeItem(atPath: output)
try fileManager.createDirectory(atPath: output, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "TwilightIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    context.cgContext.clear(canvas)

    // macOS icon silhouette with the same orange-to-blue gradient as the in-app mark.
    let tile = NSBezierPath(roundedRect: NSRect(x: 72 * scale, y: 72 * scale, width: 880 * scale, height: 880 * scale), xRadius: 215 * scale, yRadius: 215 * scale)
    tile.addClip()
    let gradient = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.953, green: 0.533, blue: 0.231, alpha: 1), 0.0),
        (NSColor(calibratedRed: 0.922, green: 0.467, blue: 0.694, alpha: 1), 0.48),
        (NSColor(calibratedRed: 0.200, green: 0.612, blue: 1.000, alpha: 1), 1.0)
    )!
    gradient.draw(in: tile, angle: -45)

    let white = NSColor.white.withAlphaComponent(0.96)
    white.setStroke()
    white.setFill()
    let stroke = max(1.4, 34 * scale)

    // Horizon.
    let horizon = NSBezierPath()
    horizon.lineWidth = stroke
    horizon.lineCapStyle = .round
    horizon.move(to: NSPoint(x: 292 * scale, y: 402 * scale))
    horizon.line(to: NSPoint(x: 732 * scale, y: 402 * scale))
    horizon.stroke()

    // Half sun rising above the horizon.
    let sunRect = NSRect(x: 387 * scale, y: 402 * scale, width: 250 * scale, height: 250 * scale)
    let sun = NSBezierPath()
    sun.lineWidth = stroke
    sun.lineCapStyle = .round
    sun.appendArc(withCenter: NSPoint(x: sunRect.midX, y: sunRect.minY), radius: sunRect.width / 2, startAngle: 0, endAngle: 180)
    sun.stroke()

    // Rays.
    let center = NSPoint(x: 512 * scale, y: 527 * scale)
    for degrees in stride(from: 20.0, through: 160.0, by: 35.0) {
        let angle = CGFloat(degrees * .pi / 180)
        let inner = CGFloat(182) * scale
        let outer = CGFloat(252) * scale
        let ray = NSBezierPath()
        ray.lineWidth = stroke
        ray.lineCapStyle = .round
        ray.move(to: NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        ray.line(to: NSPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        ray.stroke()
    }

    // Small reflected light line underneath the horizon.
    let reflection = NSBezierPath()
    reflection.lineWidth = stroke * 0.72
    reflection.lineCapStyle = .round
    reflection.move(to: NSPoint(x: 420 * scale, y: 322 * scale))
    reflection.line(to: NSPoint(x: 604 * scale, y: 322 * scale))
    reflection.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "TwilightIcon", code: 2)
    }
    return data
}

for (name, size) in variants {
    let data = try drawIcon(size: size)
    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}

// ICNS is a big-endian chunk container. Modern macOS accepts PNG payloads for
// these standard size codes; writing it directly avoids iconutil regressions.
func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

let chunks: [(String, String)] = [
    ("ic10", "icon_512x512@2x.png"), // 1024
    ("ic09", "icon_512x512.png"),    // 512
    ("ic08", "icon_256x256.png"),    // 256
    ("ic07", "icon_128x128.png"),    // 128
    ("icp6", "icon_32x32@2x.png"),   // 64
    ("icp5", "icon_32x32.png"),      // 32
    ("icp4", "icon_16x16.png")       // 16
]

var payload = Data()
for (type, filename) in chunks {
    let png = try Data(contentsOf: URL(fileURLWithPath: output).appendingPathComponent(filename))
    payload.append(type.data(using: .ascii)!)
    payload.append(bigEndianData(UInt32(png.count + 8)))
    payload.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(payload.count + 8)))
icns.append(payload)
try icns.write(to: URL(fileURLWithPath: icnsOutput))
