import Cocoa

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctxObj = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctxObj
let cg = ctxObj.cgContext

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// --- App tile: inset rounded square with soft drop shadow (native macOS look) ---
let inset: CGFloat = 96
let tile = NSRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let radius: CGFloat = (S - inset*2) * 0.225
let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -22), blur: 50,
             color: col(0,0,0,0.35).cgColor)
// clip to tile and paint the HDR gradient (cyan -> violet, evokes wide-gamut color)
tilePath.addClip()
let grad = NSGradient(colors: [col(0, 200, 255), col(91, 70, 246), col(123, 47, 247)],
                      atLocations: [0.0, 0.6, 1.0], colorSpace: .sRGB)!
grad.draw(in: tile, angle: -90)
cg.restoreGState()

// re-clip (without shadow) for interior art
cg.saveGState()
tilePath.addClip()

// --- Sun ---
let sun = NSBezierPath(ovalIn: NSRect(x: tile.minX + tile.width*0.18,
                                      y: tile.minY + tile.height*0.60,
                                      width: tile.width*0.20, height: tile.width*0.20))
col(255, 255, 255, 0.95).setFill()
sun.fill()

// --- Mountains (two white silhouettes, layered) ---
func mountain(_ peaks: [(CGFloat, CGFloat)], _ baseY: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: tile.minX, y: tile.minY + tile.height*baseY))
    for (x, y) in peaks {
        p.line(to: NSPoint(x: tile.minX + tile.width*x, y: tile.minY + tile.height*y))
    }
    p.line(to: NSPoint(x: tile.maxX, y: tile.minY + tile.height*baseY))
    p.line(to: NSPoint(x: tile.maxX, y: tile.minY))
    p.line(to: NSPoint(x: tile.minX, y: tile.minY))
    p.close()
    color.setFill()
    p.fill()
}
// back range (softer)
mountain([(0.18, 0.42), (0.34, 0.30), (0.52, 0.52), (0.70, 0.34), (0.88, 0.50)],
         0.30, col(255, 255, 255, 0.55))
// front range (bright)
mountain([(0.10, 0.20), (0.30, 0.46), (0.46, 0.24), (0.66, 0.40), (0.82, 0.18), (0.95, 0.30)],
         0.16, col(255, 255, 255, 0.98))

cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: "/tmp/heic-icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
