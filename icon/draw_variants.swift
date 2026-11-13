import AppKit
// Renders five NotchMic logo directions (1024px each) plus a labelled comparison sheet.
let S: CGFloat = 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a) }

func canvas(_ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.shadowBlurRadius = 28; sh.shadowOffset = NSSize(width: 0, height: -12); sh.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    draw()
    NSGraphicsContext.current = nil
    return rep
}
func background(_ top: NSColor, _ bottom: NSColor) { NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90) }
func notch(width: CGFloat = 250, height: CGFloat = 70, color: NSColor = .black, camera: Bool = true) -> NSRect {
    let r = NSRect(x: S/2 - width/2, y: body.maxY - height, width: width, height: height + 40)
    NSGraphicsContext.saveGraphicsState(); shape.addClip(); color.setFill()
    NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34).fill(); NSGraphicsContext.restoreGraphicsState()
    if camera { rgb(0.25, 0.25, 0.28).setFill(); NSBezierPath(ovalIn: NSRect(x: S/2 - 11, y: body.maxY - 46, width: 22, height: 22)).fill() }
    return r
}
func symbol(_ name: String, size: CGFloat, color: NSColor, center: NSPoint, glow: NSColor? = nil) -> NSRect {
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: size, weight: .semibold))!
    let tinted = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
    let r = NSRect(x: center.x - img.size.width/2, y: center.y - img.size.height/2, width: img.size.width, height: img.size.height)
    NSGraphicsContext.saveGraphicsState()
    if let g = glow { let s = NSShadow(); s.shadowColor = g; s.shadowBlurRadius = 60; s.set() }
    tinted.draw(in: r); NSGraphicsContext.restoreGraphicsState()
    return r
}
func arcs(_ c: NSPoint, from a: CGFloat, to b: CGFloat, color: NSColor) {
    for (i, r) in [CGFloat(70), 125].enumerated() {
        let p = NSBezierPath(); p.appendArc(withCenter: c, radius: r, startAngle: a, endAngle: b); p.lineWidth = 30; p.lineCapStyle = .round
        color.withAlphaComponent(i == 0 ? 1 : 0.6).setStroke(); p.stroke()
    }
}

let styles: [(String, String, () -> Void)] = [
    ("1_bezel", "Bezel", {
        background(rgb(0.16, 0.17, 0.24), rgb(0.04, 0.04, 0.07))
        let m = symbol("mic.fill", size: 360, color: .white, center: NSPoint(x: S/2, y: S/2), glow: rgb(0.35, 0.6, 1, 0.75))
        arcs(NSPoint(x: m.maxX + 10, y: m.midY + 45), from: -40, to: 40, color: rgb(0.38, 0.65, 1))
        arcs(NSPoint(x: m.minX - 10, y: m.midY + 45), from: 140, to: 220, color: rgb(0.38, 0.65, 1))
    }),
    ("2_waveform", "Waveform", {
        background(rgb(0.55, 0.30, 0.95), rgb(0.95, 0.30, 0.55)); _ = notch()
        let heights: [CGFloat] = [120, 230, 340, 440, 340, 230, 120, 200, 90]
        let w: CGFloat = 46, gap: CGFloat = 26, total = CGFloat(heights.count) * w + CGFloat(heights.count - 1) * gap
        for (i, h) in heights.enumerated() {
            let x = S/2 - total/2 + CGFloat(i) * (w + gap)
            NSColor.white.withAlphaComponent(0.95).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: S/2 - 40 - h/2, width: w, height: h), xRadius: w/2, yRadius: w/2).fill()
        }
    }),
    ("3_aluminum", "Aluminum", {
        background(rgb(0.93, 0.94, 0.96), rgb(0.70, 0.72, 0.76)); _ = notch()
        let m = symbol("mic.fill", size: 330, color: rgb(0.10, 0.10, 0.12), center: NSPoint(x: S/2, y: S/2 - 50))
        for (i, dx) in [CGFloat(-38), 38].enumerated() {
            rgb(0.15, 0.45, 1, i == 0 ? 1 : 0.55).setFill()
            NSBezierPath(ovalIn: NSRect(x: m.maxX + 70 + dx, y: m.maxY - 40, width: 56, height: 56)).fill()
        }
    }),
    ("4_minimal", "Minimal", {
        background(rgb(0.08, 0.08, 0.09), rgb(0.02, 0.02, 0.03))
        let r = NSRect(x: S/2 - 280, y: S/2 - 110, width: 560, height: 220)
        NSColor.black.setFill(); NSBezierPath(roundedRect: r, xRadius: 110, yRadius: 110).fill()
        rgb(0.22, 0.22, 0.25).setStroke(); let ring = NSBezierPath(roundedRect: r, xRadius: 110, yRadius: 110); ring.lineWidth = 6; ring.stroke()
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow(); s.shadowColor = rgb(1, 0.6, 0.1); s.shadowBlurRadius = 50; s.set()
        rgb(1, 0.62, 0.12).setFill(); NSBezierPath(ovalIn: NSRect(x: r.maxX - 170, y: r.midY - 40, width: 80, height: 80)).fill()
        NSGraphicsContext.restoreGraphicsState()
        rgb(0.25, 0.25, 0.28).setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX + 100, y: r.midY - 25, width: 50, height: 50)).fill()
    }),
    ("5_bubble", "Speech bubble", {
        background(rgb(0.20, 0.62, 1), rgb(0.05, 0.32, 0.85)); _ = notch()
        let b = NSRect(x: S/2 - 250, y: S/2 - 200, width: 500, height: 380)
        let bubble = NSBezierPath(roundedRect: b, xRadius: 150, yRadius: 150)
        bubble.move(to: NSPoint(x: b.minX + 120, y: b.minY + 30)); bubble.line(to: NSPoint(x: b.minX + 60, y: b.minY - 80)); bubble.line(to: NSPoint(x: b.minX + 230, y: b.minY + 10)); bubble.close()
        NSGraphicsContext.saveGraphicsState(); let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.25); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -10); s.set()
        NSColor.white.setFill(); bubble.fill(); NSGraphicsContext.restoreGraphicsState()
        _ = symbol("mic.fill", size: 210, color: rgb(0.08, 0.40, 0.95), center: NSPoint(x: b.midX, y: b.midY))
    }),
]

var images: [(String, NSImage)] = []
for (file, label, draw) in styles {
    let rep = canvas(draw)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(file).png"))
    let img = NSImage(size: NSSize(width: S, height: S)); img.addRepresentation(rep); images.append((label, img))
}
// comparison sheet
let tile: CGFloat = 360, pad: CGFloat = 40, W = CGFloat(images.count) * (tile + pad) + pad, H = tile + 2 * pad + 60
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
rgb(0.96, 0.96, 0.97).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
for (i, (label, img)) in images.enumerated() {
    let x = pad + CGFloat(i) * (tile + pad)
    img.draw(in: NSRect(x: x, y: pad + 60, width: tile, height: tile))
    let t = "\(i + 1). \(label)" as NSString
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: rgb(0.15, 0.15, 0.18)]
    t.draw(at: NSPoint(x: x + tile/2 - t.size(withAttributes: attrs).width/2, y: pad), withAttributes: attrs)
}
NSGraphicsContext.current = nil
try! sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "NotchMic_logo_options.png"))
