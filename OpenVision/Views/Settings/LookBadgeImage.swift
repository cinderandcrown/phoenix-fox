// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Draws the marker for an assistant: a QR code whose text is `PFX:BOT:` and the name.

import CoreImage
import UIKit

enum LookBadgeImage {
    /// The marker as a picture, or nil when the name cannot be written in one.
    ///
    /// The code is drawn with twelve points to each of its squares and no smoothing, so
    /// it stays sharp when it is shown large on a computer screen.
    static func marker(for name: String) -> UIImage? {
        guard let payload = LookMarker.payload(for: name),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        // Medium correction: the code survives a reflection on the screen and stays coarse.
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
