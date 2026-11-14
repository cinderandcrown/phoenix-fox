// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Draws a SwiftUI view to a picture and checks it against a reference picture kept in
// OpenVisionTests/__Snapshots__.
//
// There is no third-party snapshot library here. The view is put in a window the size of
// an iPhone screen, drawn with UIKit, and compared with PixelDiff.
//
// When a reference is missing the picture is recorded in its place and the test checks
// only that something was drawn. CI uploads the folder, so a recorded picture can be
// looked at and committed from a machine that is not a Mac. docs/DESIGN.md has the steps.

import SwiftUI
import UIKit
import XCTest

@MainActor
enum SnapshotHarness {
    /// The folder next to this file where references are kept, for the iOS that is running.
    static func referenceFolder(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent(SnapshotPlan.folder(osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion))
    }

    /// Where a picture that did not match is written, with a picture of what changed.
    static func failureFolder(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent("failed")
    }

    // MARK: - Drawing

    /// Draws `view` as it would look filling an iPhone screen.
    static func draw<Content: View>(_ view: Content, variant: SnapshotVariant) -> UIImage {
        let size = CGSize(width: SnapshotPlan.width, height: SnapshotPlan.height)
        let root = view
            .dynamicTypeSize(variant.usesLargeType ? .accessibility3 : .large)
            .environment(\.colorScheme, variant.isDark ? .dark : .light)
        let host = UIHostingController(rootView: root)
        // The simulator's notch and home indicator would otherwise move the layout.
        host.safeAreaRegions = []

        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = variant.isDark ? .dark : .light
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // One turn of the run loop, so SwiftUI has laid out and drawn.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(SnapshotPlan.scale)
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            if !host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) {
                host.view.layer.render(in: context.cgContext)
            }
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    /// The picture as plain bytes in sRGB, whatever format UIKit drew it in.
    static func pixels(of image: UIImage) -> PixelImage? {
        guard let source = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = source.width
        let height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? PixelImage(width: width, height: height, rgba: bytes) : nil
    }

    static func image(from pixels: PixelImage) -> UIImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels.rgba) as CFData),
              let image = CGImage(
                width: pixels.width, height: pixels.height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.width * 4,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - Checking

    /// Draws `view`, then compares it with its reference or records it when there is none.
    static func check<Content: View>(
        _ view: Content,
        named name: String,
        variant: SnapshotVariant,
        in test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let image = draw(view, variant: variant)
        guard let actual = pixels(of: image) else {
            return XCTFail("\(name): the picture could not be read.", file: file, line: line)
        }

        // True with or without a reference: the right size, and something was drawn.
        XCTAssertEqual(actual.width, SnapshotPlan.width * SnapshotPlan.scale, "\(name): width", file: file, line: line)
        XCTAssertEqual(actual.height, SnapshotPlan.height * SnapshotPlan.scale, "\(name): height", file: file, line: line)
        XCTAssertFalse(PixelDiff.isBlank(actual), "\(name): nothing was drawn.", file: file, line: line)

        let folder = referenceFolder(file: file)
        let reference = folder.appendingPathComponent("\(name).png")

        guard let saved = UIImage(contentsOfFile: reference.path), let expected = pixels(of: saved) else {
            record(image, at: reference, named: name, in: test)
            return
        }

        let verdict = PixelDiff.compare(reference: expected, actual: actual)
        guard !verdict.passes else { return }

        let failures = failureFolder(file: file)
        write(image, to: failures.appendingPathComponent("\(name).actual.png"))
        attach(image, named: "\(name).actual", to: test)
        if let marked = PixelDiff.marked(reference: expected, actual: actual), let picture = self.image(from: marked) {
            write(picture, to: failures.appendingPathComponent("\(name).changed.png"))
            attach(picture, named: "\(name).changed", to: test)
        }
        XCTFail(
            "\(name): \(verdict.summary) The new picture and a picture of what changed are in __Snapshots__/failed. "
            + "If the change is meant, replace the reference with the new picture.",
            file: file, line: line
        )
    }

    private static func record(_ image: UIImage, at url: URL, named name: String, in test: XCTestCase) {
        write(image, to: url)
        attach(image, named: "\(name).recorded", to: test)
        print("[Snapshot] No reference for \(name). Recorded \(url.path)")
    }

    private static func write(_ image: UIImage, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.pngData()?.write(to: url)
        } catch {
            // The pictures are still attached to the test result when the folder cannot be written.
            print("[Snapshot] Could not write \(url.path): \(error.localizedDescription)")
        }
    }

    private static func attach(_ image: UIImage, named name: String, to test: XCTestCase) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
