// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The part of snapshot testing that is arithmetic: comparing two pictures, deciding
// whether they are the same, and naming the files. It uses Foundation only, so it is
// tested on its own. SnapshotHarness.swift draws the pictures.

import Foundation

/// A picture as rows of red, green, blue, alpha bytes.
struct PixelImage: Equatable {
    let width: Int
    let height: Int
    private(set) var rgba: [UInt8]

    /// Nil when there are not exactly four bytes for every pixel.
    init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// One color everywhere.
    init(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        rgba = [red, green, blue, alpha].repeated(self.width * self.height)
    }

    subscript(x: Int, y: Int) -> [UInt8] {
        get {
            let start = (y * width + x) * 4
            return Array(rgba[start..<start + 4])
        }
        set {
            precondition(newValue.count == 4)
            let start = (y * width + x) * 4
            rgba.replaceSubrange(start..<start + 4, with: newValue)
        }
    }
}

private extension Array {
    func repeated(_ times: Int) -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count * times)
        for _ in 0..<times { result.append(contentsOf: self) }
        return result
    }
}

enum PixelDiff {
    /// How far one channel of one pixel may be from the reference and still count as the
    /// same. Antialiased edges land a few steps apart between machines.
    static let channelTolerance = 8
    /// The share of pixels that may be outside the tolerance. One in five hundred: a moved
    /// line of text is far more than this, a different rounding of a few edges is less.
    static let allowedFraction = 0.002

    struct Report: Equatable {
        let total: Int
        let differing: Int
        /// The largest difference found in any channel.
        let largestDelta: Int

        var fraction: Double { total == 0 ? 0 : Double(differing) / Double(total) }
    }

    enum Verdict: Equatable {
        case same(Report)
        case different(Report)
        case sizeChanged(reference: String, actual: String)

        var passes: Bool {
            if case .same = self { return true }
            return false
        }

        /// One sentence for a test failure.
        var summary: String {
            switch self {
            case .same(let report):
                return report.differing == 0
                    ? "The picture matches its reference exactly."
                    : "The picture matches its reference. \(report.differing) of \(report.total) pixels are slightly off, within tolerance."
            case .different(let report):
                let percent = (report.fraction * 1000).rounded() / 10
                return "The picture differs from its reference in \(report.differing) of \(report.total) pixels (\(percent)%). The largest difference in a channel is \(report.largestDelta) of 255."
            case .sizeChanged(let reference, let actual):
                return "The picture is \(actual) and its reference is \(reference)."
            }
        }
    }

    static func compare(
        reference: PixelImage,
        actual: PixelImage,
        channelTolerance: Int = PixelDiff.channelTolerance,
        allowedFraction: Double = PixelDiff.allowedFraction
    ) -> Verdict {
        guard reference.width == actual.width, reference.height == actual.height else {
            return .sizeChanged(
                reference: "\(reference.width) by \(reference.height)",
                actual: "\(actual.width) by \(actual.height)"
            )
        }
        var differing = 0
        var largest = 0
        let old = reference.rgba
        let new = actual.rgba
        var index = 0
        while index < old.count {
            var delta = 0
            for channel in 0..<4 {
                delta = max(delta, abs(Int(old[index + channel]) - Int(new[index + channel])))
            }
            if delta > channelTolerance { differing += 1 }
            largest = max(largest, delta)
            index += 4
        }
        let report = Report(total: reference.width * reference.height, differing: differing, largestDelta: largest)
        return report.fraction <= allowedFraction ? .same(report) : .different(report)
    }

    /// Every pixel is the same color: nothing was drawn.
    static func isBlank(_ image: PixelImage) -> Bool {
        let first = image[0, 0]
        var index = 0
        while index < image.rgba.count {
            for channel in 0..<4 where image.rgba[index + channel] != first[channel] { return false }
            index += 4
        }
        return true
    }

    /// The reference, faded, with every pixel that changed marked in magenta. Nil when the
    /// two are different sizes.
    static func marked(reference: PixelImage, actual: PixelImage, channelTolerance: Int = PixelDiff.channelTolerance) -> PixelImage? {
        guard reference.width == actual.width, reference.height == actual.height else { return nil }
        var bytes = reference.rgba
        var index = 0
        while index < bytes.count {
            var delta = 0
            for channel in 0..<4 {
                delta = max(delta, abs(Int(reference.rgba[index + channel]) - Int(actual.rgba[index + channel])))
            }
            if delta > channelTolerance {
                bytes[index] = 255
                bytes[index + 1] = 0
                bytes[index + 2] = 255
            } else {
                for channel in 0..<3 {
                    bytes[index + channel] = UInt8((Int(bytes[index + channel]) + 2 * 255) / 3)
                }
            }
            bytes[index + 3] = 255
            index += 4
        }
        return PixelImage(width: reference.width, height: reference.height, rgba: bytes)
    }
}

// MARK: - What is drawn, and what the files are called

/// The settings a screen is drawn in.
enum SnapshotVariant: String, CaseIterable {
    /// Dark mode at the default text size: how most people will see the app.
    case dark
    /// Light mode at the default text size.
    case light
    /// Dark mode at an accessibility text size, where layouts break first.
    case darkLargeType = "dark-large-type"

    var isDark: Bool { self != .light }
    var usesLargeType: Bool { self == .darkLargeType }
}

enum SnapshotPlan {
    /// Points. The size of an iPhone screen, whatever simulator runs the tests.
    static let width = 390
    static let height = 844
    /// Pixels per point.
    static let scale = 2

    /// "home-ready-dark". Lowercase letters, digits and hyphens, so it is a safe file name.
    static func name(screen: String, state: String, variant: SnapshotVariant) -> String {
        [screen, state, variant.rawValue]
            .map { part in
                String(part.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
            }
            .joined(separator: "-")
    }

    /// References are kept for each major version of iOS, because the system draws text
    /// and materials a little differently in each.
    static func folder(osMajorVersion: Int) -> String { "ios\(osMajorVersion)" }
}
