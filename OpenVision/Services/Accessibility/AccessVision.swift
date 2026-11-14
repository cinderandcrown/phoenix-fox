// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Everything the accessibility suite sees, done on the phone with Apple's Vision framework.
//
// No frame leaves the device here. Each function takes a JPEG and returns plain values, and
// each runs off the main thread: recognizing a page of text takes a noticeable fraction of
// a second.

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// A face found in a photo, with the print used to compare it to saved people.
struct FaceInView: Sendable {
    var featurePrint: Data
    var box: FrameBox
}

enum AccessVision {
    /// The text in a photo, one fragment per line the recognizer found.
    ///
    /// - Parameter corrected: Lets the recognizer fix words against a dictionary. Right for
    ///   prose. Wrong for a drug name or a serial number, which must come back as printed.
    static func text(in jpeg: Data, corrected: Bool, fast: Bool = false) async -> [TextFragment] {
        await detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = fast ? .fast : .accurate
            request.usesLanguageCorrection = corrected
            guard (try? VNImageRequestHandler(data: jpeg, options: [:]).perform([request])) != nil else { return [] }
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return TextFragment(candidate.string, box: box(observation.boundingBox), confidence: Double(candidate.confidence))
            }
        }
    }

    /// What a screen across a desk shows: its text as printed, and any QR codes on it.
    ///
    /// The text is not corrected against a dictionary, because an assistant's name is not
    /// in one. Both are found in one pass over the frame.
    static func screen(in jpeg: Data) async -> ScreenView {
        await detached {
            let words = VNRecognizeTextRequest()
            words.recognitionLevel = .accurate
            words.usesLanguageCorrection = false
            let codes = VNDetectBarcodesRequest()
            codes.symbologies = [.qr]
            guard (try? VNImageRequestHandler(data: jpeg, options: [:]).perform([words, codes])) != nil else {
                return ScreenView()
            }
            let text = (words.results ?? []).compactMap { observation -> TextFragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return TextFragment(candidate.string, box: box(observation.boundingBox), confidence: Double(candidate.confidence))
            }
            let found = (codes.results ?? []).compactMap { observation -> CodeSighting? in
                guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                return CodeSighting(payload: payload, box: box(observation.boundingBox))
            }
            return ScreenView(text: text, codes: found)
        }
    }

    /// People, animals, and whole-frame hazards such as stairs, plus any large sign text.
    static func sightings(in jpeg: Data) async -> [Sighting] {
        await detached {
            let people = VNDetectHumanRectanglesRequest()
            people.upperBodyOnly = false
            let animals = VNRecognizeAnimalsRequest()
            let scene = VNClassifyImageRequest()
            let words = VNRecognizeTextRequest()
            words.recognitionLevel = .fast
            words.usesLanguageCorrection = false
            guard (try? VNImageRequestHandler(data: jpeg, options: [:]).perform([people, animals, scene, words])) != nil else { return [] }

            var found: [Sighting] = []
            for person in people.results ?? [] where person.confidence >= 0.5 {
                found.append(Sighting(.person, box: box(person.boundingBox)))
            }
            for animal in animals.results ?? [] {
                guard let label = animal.labels.first, label.confidence >= 0.6 else { continue }
                found.append(Sighting(.animal, box: box(animal.boundingBox), label: label.identifier.lowercased()))
            }
            // One sighting per kind: "staircase" and "stairs" scoring together are one flight.
            var kinds: Set<Sighting.Kind> = []
            for label in scene.results ?? [] where label.confidence >= 0.55 {
                guard let sighting = SceneLabels.sighting(for: label.identifier), kinds.insert(sighting.kind).inserted else { continue }
                found.append(sighting)
            }
            // Only text big enough to be a sign meant for people walking by.
            let fragments = (words.results ?? []).compactMap { observation -> TextFragment? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.5,
                      observation.boundingBox.height >= 0.045,
                      candidate.string.filter(\.isLetter).count >= 3 else { return nil }
                return TextFragment(candidate.string, box: box(observation.boundingBox), confidence: Double(candidate.confidence))
            }
            for fragment in ReadingOrder.lines(fragments).prefix(2) {
                found.append(Sighting(.sign, box: fragment.box, label: fragment.text))
            }
            return found
        }
    }

    /// Pixels from the middle of the photo, where the wearer is holding the thing they asked about.
    static func centerColors(in jpeg: Data) async -> [RGB] {
        await detached {
            guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
            let width = CGFloat(image.width), height = CGFloat(image.height)
            let middle = CGRect(x: width * 0.375, y: height * 0.375, width: width * 0.25, height: height * 0.25)
            let side = 24
            guard let patch = image.cropping(to: middle),
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return [] }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: side, height: side))
            guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
            return (0..<side * side).map { index in
                RGB(Double(bytes[index * 4]), Double(bytes[index * 4 + 1]), Double(bytes[index * 4 + 2]))
            }
        }
    }

    /// Up to five faces in the photo, largest first.
    static func faces(in jpeg: Data) async -> [FaceInView] {
        await detached {
            guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
            let detect = VNDetectFaceRectanglesRequest()
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([detect])) != nil else { return [] }
            let found = (detect.results ?? []).sorted { $0.boundingBox.height > $1.boundingBox.height }
            return found.prefix(5).compactMap { face in
                guard let cropped = crop(image, to: face.boundingBox) else { return nil }
                let request = VNGenerateImageFeaturePrintRequest()
                guard (try? VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])) != nil,
                      let observation = request.results?.first,
                      let data = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true) else { return nil }
                return FaceInView(featurePrint: data, box: box(face.boundingBox))
            }
        }
    }

    /// For one face, its distance to each saved person: the smallest across that person's prints.
    static func distances(from face: Data, to people: [FaceRecord]) -> [(name: String, distance: Float)] {
        guard let query = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: face) else { return [] }
        return people.compactMap { person in
            let all = person.prints.compactMap { data -> Float? in
                guard let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) else { return nil }
                var distance: Float = 0
                guard (try? query.computeDistance(&distance, to: saved)) != nil else { return nil }
                return distance
            }
            return all.min().map { (name: person.name, distance: $0) }
        }
    }

    // MARK: - Helpers

    private static func detached<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    /// Vision measures from the bottom left. Everything else here measures from the top left.
    private static func box(_ rect: CGRect) -> FrameBox {
        FrameBox(x: Double(rect.minX), y: Double(1 - rect.maxY), width: Double(rect.width), height: Double(rect.height))
    }

    /// The face with a little margin, which the feature print matches better than a tight crop.
    private static func crop(_ image: CGImage, to face: CGRect) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let margin: CGFloat = 0.15
        let rect = CGRect(
            x: (face.minX - margin * face.width) * width,
            y: (1 - face.maxY - margin * face.height) * height,
            width: face.width * (1 + 2 * margin) * width,
            height: face.height * (1 + 2 * margin) * height
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }
}
