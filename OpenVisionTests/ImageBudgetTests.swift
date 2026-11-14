// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import UIKit
import XCTest
@testable import PhoenixFox

/// A photo's size in pixels is what a cloud model charges for, and what
/// scripts/cost_model.py assumes for "one look". Run in the simulator.
final class ImageBudgetTests: XCTestCase {
    private func photo(width: CGFloat, height: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private func pixels(_ jpeg: Data?) throws -> CGSize {
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(jpeg))?.cgImage)
        return CGSize(width: image.width, height: image.height)
    }

    func testAGlassesFrameLeavesThePhoneAt432By768Pixels() throws {
        let frame = try photo(width: 720, height: 1280)
        XCTAssertEqual(try pixels(ImageBudget.jpeg(frame)), CGSize(width: 432, height: 768))
    }

    func testAWidePhotoIsHeldTo768OnItsLongEdge() throws {
        let wide = try photo(width: 4032, height: 3024)
        XCTAssertEqual(try pixels(ImageBudget.jpeg(wide)), CGSize(width: 768, height: 576))
    }

    func testASmallPhotoIsNotEnlarged() throws {
        let small = try photo(width: 320, height: 240)
        XCTAssertEqual(try pixels(ImageBudget.jpeg(small)), CGSize(width: 320, height: 240))
    }

    func testTheShrunkPhotoIsSmallerInBytes() throws {
        let frame = try photo(width: 720, height: 1280)
        XCTAssertLessThan(try XCTUnwrap(ImageBudget.jpeg(frame)).count, frame.count)
    }
}
