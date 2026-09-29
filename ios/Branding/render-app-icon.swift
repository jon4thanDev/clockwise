// Renders logo.svg onto a 1024x1024 white app icon.
// Usage (from ios/): swift Branding/render-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = URL(fileURLWithPath: "Clockwise/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Paths from logo.svg (viewBox 0 0 30 48), relative commands converted to absolute.
let bottom = CGMutablePath()
bottom.move(to: CGPoint(x: 0, y: 41.2222))
bottom.addCurve(to: CGPoint(x: 2.77778, y: 44), control1: CGPoint(x: 0, y: 42.7563), control2: CGPoint(x: 1.24365, y: 44))
bottom.addLine(to: CGPoint(x: 27.2222, y: 44))
bottom.addCurve(to: CGPoint(x: 30, y: 41.2222), control1: CGPoint(x: 28.7563, y: 44), control2: CGPoint(x: 30, y: 42.7563))
bottom.addLine(to: CGPoint(x: 30, y: 34))
bottom.addCurve(to: CGPoint(x: 15, y: 19), control1: CGPoint(x: 30, y: 25.7157), control2: CGPoint(x: 23.2843, y: 19))
bottom.addCurve(to: CGPoint(x: 0, y: 34), control1: CGPoint(x: 6.71573, y: 19), control2: CGPoint(x: 0, y: 25.7157))
bottom.closeSubpath()

let top = CGMutablePath()
top.move(to: CGPoint(x: 0, y: 6.77778))
top.addCurve(to: CGPoint(x: 2.77778, y: 4), control1: CGPoint(x: 0, y: 5.24365), control2: CGPoint(x: 1.24365, y: 4))
top.addLine(to: CGPoint(x: 27.2222, y: 4))
top.addCurve(to: CGPoint(x: 30, y: 6.77778), control1: CGPoint(x: 28.7563, y: 4), control2: CGPoint(x: 30, y: 5.24365))
top.addLine(to: CGPoint(x: 30, y: 14))
top.addCurve(to: CGPoint(x: 15, y: 29), control1: CGPoint(x: 30, y: 22.2843), control2: CGPoint(x: 23.2843, y: 29))
top.addCurve(to: CGPoint(x: 0, y: 14), control1: CGPoint(x: 6.71573, y: 29), control2: CGPoint(x: 0, y: 22.2843))
top.closeSubpath()

let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(color(0xFFFFFF))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// The drawn shape spans x 0...30, y 4...44; scale it to 600 px tall, centered, with SVG's y-down axis.
let scale: CGFloat = 15
context.translateBy(x: CGFloat(size) / 2 - 15 * scale, y: CGFloat(size) / 2 + 24 * scale)
context.scaleBy(x: scale, y: -scale)

context.addPath(bottom)
context.setFillColor(color(0x2563EB))
context.fillPath()
context.addPath(top)
context.setFillColor(color(0x60A5FA, alpha: 0.5))
context.fillPath()

let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.path)")
