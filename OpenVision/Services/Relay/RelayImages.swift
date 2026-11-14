// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import UIKit

/// Makes photos small enough for the relay, which refuses a request over 1.2 MB.
enum RelayImages {
    /// Longest side, in pixels, tried in turn until the photo fits.
    private static let sides: [CGFloat] = [1280, 960, 640, 480]
    private static let qualities: [CGFloat] = [0.7, 0.5, 0.35]

    /// Returns the photos as JPEG data whose sizes add up to at most `budget` bytes.
    /// A photo that already fits its share is passed through untouched. One that cannot be
    /// read, or cannot be made to fit, is left out rather than sent broken.
    static func fitted(_ images: [Data], budget: Int) -> [Data] {
        guard !images.isEmpty else { return [] }
        let share = budget / images.count
        return images.compactMap { fitted($0, limit: share) }
    }

    static func fitted(_ data: Data, limit: Int) -> Data? {
        if data.count <= limit { return data }
        guard let image = UIImage(data: data) else { return nil }
        for side in sides {
            let scaled = scaledDown(image, longestSide: side)
            for quality in qualities {
                if let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count <= limit {
                    return jpeg
                }
            }
        }
        return nil
    }

    private static func scaledDown(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > longestSide, longest > 0 else { return image }
        let ratio = longestSide / longest
        let target = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
