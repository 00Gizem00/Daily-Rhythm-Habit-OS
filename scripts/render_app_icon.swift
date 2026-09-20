// Legacy v1 geometric artwork, retained for reproducibility. The active icon is
// AppIcon-v2.png (see docs/branding/README.md); this script does not replace it.
// Run from the repository root: swift scripts/render_app_icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, 1])!
}
context.setFillColor(color(0.08, 0.15, 0.16))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setLineCap(.round)
context.setLineJoin(.round)
context.setLineWidth(82)
context.setStrokeColor(color(0.51, 0.79, 0.65))
context.addArc(center: CGPoint(x: 512, y: 512), radius: 306,
               startAngle: .pi * 0.23, endAngle: .pi * 1.74, clockwise: false)
context.strokePath()
let dotAngle: CGFloat = -.pi * 0.035
let dot = CGPoint(x: 512 + 306 * cos(dotAngle), y: 512 + 306 * sin(dotAngle))
context.setFillColor(color(1, 0.61, 0.49))
context.fillEllipse(in: CGRect(x: dot.x - 46, y: dot.y - 46, width: 92, height: 92))
context.setStrokeColor(color(0.97, 0.96, 0.91))
context.setLineWidth(78)
context.move(to: CGPoint(x: 364, y: 510))
context.addLine(to: CGPoint(x: 466, y: 410))
context.addLine(to: CGPoint(x: 659, y: 625))
context.strokePath()
let output = URL(fileURLWithPath: "docs/branding/app-icon-v1.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Unable to write app icon")
print(output.path)
