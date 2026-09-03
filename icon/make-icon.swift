import AppKit
// Ask for Mac icon: deep teal tile, a white speech bubble with a question mark, a small document peeking behind it.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s)); img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.62, alpha: 1), NSColor(calibratedRed: 0.06, green: 0.24, blue: 0.42, alpha: 1)])!.draw(in: tile, angle: -70)
    // document behind
    NSColor.white.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.50, y: s * 0.16, width: s * 0.30, height: s * 0.40), xRadius: s * 0.04, yRadius: s * 0.04).fill()
    for i in 0..<3 { NSColor.white.withAlphaComponent(0.5).setFill(); NSBezierPath(roundedRect: NSRect(x: s * 0.55, y: s * 0.44 - CGFloat(i) * s * 0.07, width: s * 0.20, height: s * 0.025), xRadius: s * 0.01, yRadius: s * 0.01).fill() }
    // bubble
    let bubble = NSBezierPath(roundedRect: NSRect(x: s * 0.16, y: s * 0.32, width: s * 0.54, height: s * 0.44), xRadius: s * 0.12, yRadius: s * 0.12)
    let tail = NSBezierPath(); tail.move(to: NSPoint(x: s * 0.28, y: s * 0.34)); tail.line(to: NSPoint(x: s * 0.22, y: s * 0.20)); tail.line(to: NSPoint(x: s * 0.40, y: s * 0.33)); tail.close()
    NSColor.black.withAlphaComponent(0.18).setFill(); NSBezierPath(roundedRect: NSRect(x: s * 0.16, y: s * 0.30, width: s * 0.54, height: s * 0.44), xRadius: s * 0.12, yRadius: s * 0.12).fill()
    NSColor.white.setFill(); bubble.fill(); tail.fill()
    // question mark
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.34, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.06, green: 0.24, blue: 0.42, alpha: 1), .paragraphStyle: para]
    NSAttributedString(string: "?", attributes: attrs).draw(in: NSRect(x: s * 0.16, y: s * 0.33, width: s * 0.54, height: s * 0.42))
    img.unlockFocus(); return img
}
let out = "icon/AskMac.iconset"
try? FileManager.default.removeItem(atPath: out); try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px)); NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
