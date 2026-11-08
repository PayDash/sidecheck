import AppKit
import XCTest
@testable import Sidecheck

/// Pins the crop clamp: the media always covers the viewport, scale stays in
/// 1...5, and offsets never exceed the overhang (image math uses the media's
/// own aspect; video uses the aspect-fill layer rule).
@MainActor // clamp resolves the image through WallpaperStore's caches
final class CropSpecTests: XCTestCase {
    private let viewport = CGSize(width: 100, height: 100)

    /// A real 100×200 PNG in a temp dir for the image-mode overhang math.
    private var imagePath: String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecheck-crop-test-\(UUID().uuidString).png")
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 100, height: 200))
        image.addRepresentation(rep)
        let png = rep.representation(using: .png, properties: [:])!
        try! png.write(to: url)
        return url.path
    }

    // MARK: video mode (aspect-fill rule: overhang = (scale − 1) / 2)

    func testVideoClampsOffsetsToHalfScaleOverhang() {
        let clamped = CropEditorView.clamp(
            CropSpec(scale: 3, offsetX: 5, offsetY: -5),
            mode: .video(path: "/x.mp4"), viewport: viewport
        )
        XCTAssertEqual(clamped.scale, 3)
        XCTAssertEqual(clamped.offsetX, 1, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetY, -1, accuracy: 0.0001)
    }

    func testVideoClampsScaleToBounds() {
        let small = CropEditorView.clamp(
            CropSpec(scale: 0.5, offsetX: 0, offsetY: 0),
            mode: .video(path: "/x.mp4"), viewport: viewport
        )
        XCTAssertEqual(small.scale, 1)

        let large = CropEditorView.clamp(
            CropSpec(scale: 10, offsetX: 10, offsetY: 0),
            mode: .video(path: "/x.mp4"), viewport: viewport
        )
        XCTAssertEqual(large.scale, 5)
        XCTAssertEqual(large.offsetX, 2, accuracy: 0.0001) // (5 − 1) / 2
    }

    // MARK: image mode (overhang from the media's own aspect)

    func testMissingImageClampsOffsetsToZero() {
        let clamped = CropEditorView.clamp(
            CropSpec(scale: 2, offsetX: 0.7, offsetY: -0.7),
            mode: .image(path: "/nonexistent/nope-\(UUID().uuidString).png"),
            viewport: viewport
        )
        XCTAssertEqual(clamped.scale, 2)
        XCTAssertEqual(clamped.offsetX, 0, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetY, 0, accuracy: 0.0001)
    }

    func testImageOffsetsNeverShowAGap() {
        // 100×200 media in a 100×100 viewport: at scale 1 only the height
        // overhangs (±0.5); the width is flush, so offsetX must pin to 0.
        let path = imagePath
        defer { try? FileManager.default.removeItem(atPath: path) }

        let clamped = CropEditorView.clamp(
            CropSpec(scale: 1, offsetX: 0.3, offsetY: -0.9),
            mode: .image(path: path), viewport: viewport
        )
        XCTAssertEqual(clamped.scale, 1)
        XCTAssertEqual(clamped.offsetX, 0, accuracy: 0.0001)
        XCTAssertEqual(clamped.offsetY, -0.5, accuracy: 0.0001)

        // At scale 2 the media is 200×400: overhangs grow to ±0.5 x / ±1.5 y.
        let zoomed = CropEditorView.clamp(
            CropSpec(scale: 2, offsetX: 5, offsetY: 5),
            mode: .image(path: path), viewport: viewport
        )
        XCTAssertEqual(zoomed.offsetX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(zoomed.offsetY, 1.5, accuracy: 0.0001)
    }
}
