import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func drawIcon(size: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = CGPath(
        roundedRect: CGRect(x: 92, y: 94, width: 840, height: 840),
        cornerWidth: 190, cornerHeight: 190, transform: nil
    )

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -9), blur: 20, color: rgb(0.12, 0.21, 0.39, 0.20))
    context.setFillColor(rgb(0.80, 0.88, 0.98))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [rgb(0.91, 0.96, 1), rgb(0.72, 0.82, 0.97)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 365, y: 934), end: CGPoint(x: 660, y: 94),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()

    let center = CGPoint(x: 512, y: 477)
    let radius: CGFloat = 186
    let stopwatch = CGMutablePath()
    stopwatch.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2))
    stopwatch.move(to: CGPoint(x: 512, y: 663))
    stopwatch.addLine(to: CGPoint(x: 512, y: 731))
    stopwatch.move(to: CGPoint(x: 466, y: 731))
    stopwatch.addLine(to: CGPoint(x: 558, y: 731))
    stopwatch.move(to: center)
    stopwatch.addLine(to: CGPoint(x: 597, y: 562))

    context.setStrokeColor(rgb(0.15, 0.32, 0.59))
    context.setLineWidth(46)
    context.setLineCap(.round)
    context.addPath(stopwatch)
    context.strokePath()

    return context.makeImage()!
}

// ICNS stores each PNG in a four-character chunk. The @2x variants have their own chunk types.
func chunk(_ type: String, payload: Data) -> Data {
    var data = Data(type.utf8)
    var length = UInt32(payload.count + 8).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}

let representations = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)
]
var payload = Data()
for (type, size) in representations {
    let image = NSBitmapImageRep(cgImage: drawIcon(size: size))
    let png = image.representation(using: .png, properties: [:])!
    payload.append(chunk(type, payload: png))
}
try chunk("icns", payload: payload).write(to: output, options: .atomic)
