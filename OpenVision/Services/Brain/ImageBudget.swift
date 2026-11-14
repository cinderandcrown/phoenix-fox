// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - shrink a glasses photo before it leaves the phone.

import UIKit

enum ImageBudget {
    static func jpeg(_ data: Data?, maxEdge: CGFloat = 768, quality: CGFloat = 0.45) -> Data? {
        guard let data, let image = UIImage(data: data) else { return data }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.jpegData(compressionQuality: quality)
    }
}
