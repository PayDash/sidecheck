// Renders the Sidecheck app icon from a source image.
// The image is aspect-filled and center-cropped onto Apple's Big Sur icon
// grid: an 824x824 rounded rect (corner radius 185.4) centered on a
// 1024x1024 transparent canvas, with a subtle native-style drop shadow.
// Usage: swift Scripts/make_icon.swift <source-image> <output.png>

import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("usage: swift Scripts/make_icon.swift <source-image> <output.png>\n", stderr)
    exit(2)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

// Load the source upright (applies EXIF orientation) at up to 1024px.
let sourceOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: 1024,
]
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let logo = CGImageSourceCreateThumbnailAtIndex(source, 0, sourceOptions as CFDictionary) else {
    fputs("error: could not load \(sourceURL.path)\n", stderr)
    exit(1)
}

let canvas: CGFloat = 1024
let inset: CGFloat = 100 // 824x824 shape on the 1024 canvas
let radius: CGFloat = 185.4
let shapeRect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let shapePath = CGPath(roundedRect: shapeRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

guard let ctx = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("error: could not create bitmap context\n", stderr)
    exit(1)
}
ctx.interpolationQuality = .high

// Drop shadow: paint the shape once with a shadow, then cover it fully.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
ctx.addPath(shapePath)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Draw the logo aspect-filled (center-cropped) inside the shape.
let logoWidth = CGFloat(logo.width)
let logoHeight = CGFloat(logo.height)
let scale = max(shapeRect.width / logoWidth, shapeRect.height / logoHeight)
let drawRect = CGRect(
    x: shapeRect.midX - logoWidth * scale / 2,
    y: shapeRect.midY - logoHeight * scale / 2,
    width: logoWidth * scale,
    height: logoHeight * scale
)
ctx.saveGState()
ctx.addPath(shapePath)
ctx.clip()
ctx.draw(logo, in: drawRect)
ctx.restoreGState()

guard let rendered = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("error: could not write \(outputURL.path)\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("error: could not finalize \(outputURL.path)\n", stderr)
    exit(1)
}
