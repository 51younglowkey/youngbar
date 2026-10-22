// Builds the YoungBar app icon from Resources/AppIcon-source.jpg.
// The source art keeps its hand-drawn frame; it is placed on the picture's own
// pink background inside a standard macOS rounded-square mask.
// Usage: swift Scripts/make-icon.swift <out.png>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/YoungBar-1024.png"
let source = "Resources/AppIcon-source.jpg"

guard let art = NSImage(contentsOfFile: source),
      let tiff = art.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: tiff) else {
    fatalError("cannot read \(source)")
}

let side = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("cannot allocate bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: side, height: side)
NSColor.clear.setFill()
canvas.fill()

// Sample the picture's outer pink so the rounded background is seamless.
let pink = sourceRep.colorAt(x: 20, y: 20) ?? NSColor(calibratedRed: 0.97, green: 0.84, blue: 0.88, alpha: 1)

let inset: CGFloat = 64
let squircle = NSBezierPath(roundedRect: canvas.insetBy(dx: inset, dy: inset),
                            xRadius: 224, yRadius: 224)
pink.setFill()
squircle.fill()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
// Keep the entire hand-drawn frame visible inside the rounded mask.
let artSide: CGFloat = 800
let artRect = NSRect(x: (CGFloat(side) - artSide) / 2,
                     y: (CGFloat(side) - artSide) / 2,
                     width: artSide, height: artSide)
art.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

// Hairline highlight keeps the rounded edge legible on dark wallpapers.
NSColor.white.withAlphaComponent(0.10).setStroke()
squircle.lineWidth = 3
squircle.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print(output)
