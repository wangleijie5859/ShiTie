// Run with: swift scripts/make-icon.swift
// Package the checked-in artwork at every native macOS icon size, preserving alpha.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/Brand/AppIcon.png")
guard let artwork = NSImage(contentsOf: source) else {
    fputs("Cannot read Resources/Brand/AppIcon.png\n", stderr)
    exit(1)
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
var icns = Data("icns".utf8)
icns.append(contentsOf: [0, 0, 0, 0])
for (size, code) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    NSGraphicsContext.current?.imageInterpolation = .high
    artwork.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    icns.append(contentsOf: code.utf8)
    var length = UInt32(png.count + 8).bigEndian
    withUnsafeBytes(of: &length) { icns.append(contentsOf: $0) }
    icns.append(png)
}
var total = UInt32(icns.count).bigEndian
withUnsafeBytes(of: &total) { icns.replaceSubrange(4..<8, with: $0) }
try icns.write(to: output, options: .atomic)
print("Created Resources/AppIcon.icns")
