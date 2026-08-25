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

let paper = col(232, 227, 217)
let ink   = col(46, 46, 41)

// --- App tile: warm paper with a soft drop shadow ---
let inset: CGFloat = 96
let tile = NSRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let radius: CGFloat = (S - inset*2) * 0.225
let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -22), blur: 50,
             color: col(0,0,0,0.35).cgColor)
paper.setFill()
tilePath.fill()
cg.restoreGState()

// --- Interior art: ink circle with a paper photo glyph ---
cg.saveGState()
tilePath.addClip()

let circleCenter = NSPoint(x: tile.midX, y: tile.midY)
let circleRadius = tile.width * 0.31
let circle = NSBezierPath(ovalIn: NSRect(
    x: circleCenter.x - circleRadius,
    y: circleCenter.y - circleRadius,
    width: circleRadius * 2,
    height: circleRadius * 2))
ink.setFill()
circle.fill()

// Photo glyph, centered in the circle.
let glyphW = circleRadius * 1.15
let glyphH = glyphW * 0.74
let glyphRect = NSRect(
    x: circleCenter.x - glyphW/2,
    y: circleCenter.y - glyphH/2,
    width: glyphW,
    height: glyphH)
let glyphRadius = glyphW * 0.08

let frame = NSBezierPath(roundedRect: glyphRect, xRadius: glyphRadius, yRadius: glyphRadius)
frame.lineWidth = glyphW * 0.065
paper.setStroke()
frame.stroke()

let strokeW = glyphW * 0.055
let mountains = NSBezierPath()
mountains.move(to: NSPoint(x: glyphRect.minX + glyphW*0.14,
                           y: glyphRect.minY + glyphH*0.62))
mountains.line(to: NSPoint(x: glyphRect.midX,
                           y: glyphRect.minY + glyphH*0.34))
mountains.line(to: NSPoint(x: glyphRect.maxX - glyphW*0.14,
                           y: glyphRect.minY + glyphH*0.62))
mountains.lineWidth = strokeW
paper.setStroke()
mountains.stroke()

let sunSize = glyphW * 0.15
let sun = NSBezierPath(ovalIn: NSRect(
    x: glyphRect.maxX - glyphW*0.34,
    y: glyphRect.maxY - glyphH*0.43,
    width: sunSize,
    height: sunSize))
paper.setFill()
sun.fill()

cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: "/tmp/heic-icon-1024.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
