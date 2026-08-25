import Cocoa
import CoreText

let referenceSize: CGFloat = 1024
let paper = NSColor(srgbRed: 232/255, green: 227/255, blue: 217/255, alpha: 1)
let ink = NSColor(srgbRed: 46/255, green: 46/255, blue: 41/255, alpha: 1)

let fontURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fonts/Lato-Bold.ttf")
var fontRegistrationError: Unmanaged<CFError>?
if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontRegistrationError),
   let error = fontRegistrationError?.takeRetainedValue() {
    fputs("warning: could not register Lato Bold; using the system font: \(error)\n", stderr)
}

func scaled(_ value: CGFloat, to size: CGFloat) -> CGFloat {
    value * size / referenceSize
}

func drawCompactMonogram16(center: NSPoint) {
    // Four lowercase letters cannot remain distinct inside the 10 px circle,
    // so the legacy 1x rendition uses the same h-plus-dot shorthand language.
    let font = NSFont(name: "Lato-Bold", size: 8)
        ?? NSFont.systemFont(ofSize: 8, weight: .bold)
    let monogram = NSAttributedString(string: "h.", attributes: [
        .font: font,
        .foregroundColor: paper,
        .kern: 0.2,
    ])
    let monogramSize = monogram.size()
    monogram.draw(at: NSPoint(
        x: round(center.x - monogramSize.width / 2),
        y: round(center.y - monogramSize.height / 2)))
}

func renderIcon(pixelSize: Int, to outputURL: URL, opticallyAdjusted: Bool = false) throws {
    let size = CGFloat(pixelSize)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // Match the HBAI whisper-drop icon's warm-paper tile geometry.
    let inset = scaled(64, to: size)
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = NSBezierPath(
        roundedRect: tile,
        xRadius: scaled(208, to: size),
        yRadius: scaled(208, to: size))
    paper.setFill()
    tilePath.fill()

    // Ink circle and paper monogram, modeled directly on whisper-drop.
    context.cgContext.saveGState()
    tilePath.addClip()

    let circleCenter = NSPoint(x: tile.midX, y: tile.midY)
    let circleRadius = scaled(306, to: size)
    let circle = NSBezierPath(ovalIn: NSRect(
        x: circleCenter.x - circleRadius,
        y: circleCenter.y - circleRadius,
        width: circleRadius * 2,
        height: circleRadius * 2))
    ink.setFill()
    circle.fill()

    if opticallyAdjusted && pixelSize == 16 {
        drawCompactMonogram16(center: circleCenter)
    } else {
        // Small icon sizes need native rasterization, taller type, and extra
        // tracking; downsampling the 1024 px wordmark merges the letters.
        let fontScale = opticallyAdjusted ? 0.25 : 220 / referenceSize
        let fontSize = size * fontScale
        let font = NSFont(name: "Lato-Bold", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: paper,
        ]
        if opticallyAdjusted {
            attributes[.kern] = 0.35
        } else {
            attributes[.strokeColor] = paper
            attributes[.strokeWidth] = -3.0
        }

        let monogram = NSAttributedString(string: "heic", attributes: attributes)
        let monogramSize = monogram.size()
        let showsTerminalDot = !opticallyAdjusted || pixelSize >= 64
        let dotRadius = max(scaled(8, to: size), opticallyAdjusted ? 0.75 : 0)
        let dotGap = scaled(11, to: size)
        let lockupWidth = monogramSize.width
            + (showsTerminalDot ? dotGap + dotRadius * 2 : 0)
        let monogramOrigin = NSPoint(
            x: circleCenter.x - lockupWidth / 2,
            y: circleCenter.y - monogramSize.height / 2)
        monogram.draw(at: monogramOrigin)

        if showsTerminalDot {
            // A terminal dot echoes the reference icon's punctuation accents.
            let dotCenter = NSPoint(
                x: monogramOrigin.x + monogramSize.width + dotGap + dotRadius,
                y: monogramOrigin.y + monogramSize.height * 0.29)
            let dot = NSBezierPath(ovalIn: NSRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2))
            paper.setFill()
            dot.fill()
        }
    }

    context.cgContext.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    try rep.representation(using: .png, properties: [:])!.write(to: outputURL)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--small-iconset" {
    let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let renditions = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
    ]
    for (pixelSize, filename) in renditions {
        try renderIcon(
            pixelSize: pixelSize,
            to: iconsetURL.appendingPathComponent(filename),
            opticallyAdjusted: true)
    }
    print("wrote optically tuned small icon renditions")
} else {
    let outputURL = URL(fileURLWithPath: "/tmp/heic-icon-1024.png")
    try renderIcon(pixelSize: 1024, to: outputURL)
    print("wrote \(outputURL.path)")
}
