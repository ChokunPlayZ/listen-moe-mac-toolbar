import AppKit

// Draw locally, so building the app needs no downloaded artwork or dependencies.
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let bounds = NSRect(x: 70, y: 70, width: 884, height: 884)
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 200, yRadius: 200)
        NSGradient(colors: [
            NSColor(srgbRed: 0.20, green: 0.15, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 0.075, green: 0.075, blue: 0.11, alpha: 1),
        ])!.draw(in: shape, angle: -60)
        NSColor(srgbRed: 1, green: 0.23, blue: 0.47, alpha: 1).setFill()
        let heights: [CGFloat] = [160, 310, 470, 260, 160]
        for (index, height) in heights.enumerated() {
            NSBezierPath(
                roundedRect: NSRect(x: 273 + CGFloat(index) * 100, y: (1024 - height) / 2, width: 54, height: height),
                xRadius: 27, yRadius: 27
            ).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
