// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import AVFoundation
import UIKit
import XCTest
@testable import PhoenixFox

/// The accessibility suite's platform layer, run in the simulator: the sealed store, the
/// pixel and text readers, and whole spoken turns through the coordinator.
@MainActor
final class AccessPlatformTests: XCTestCase {
    private func picture(size: CGSize = CGSize(width: 800, height: 600), draw: (CGRect) -> Void) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: size)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(bounds) }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private func solid(_ color: UIColor) throws -> Data {
        try picture { bounds in
            color.setFill()
            UIRectFill(bounds)
        }
    }

    // MARK: - Store

    func testTheStoreSealsWhatItSavesAndReadsItBack() throws {
        let name = "test-\(UUID().uuidString)"
        let routine = Routine(name: "Morning", steps: ["Take the blue pill", "Drink water"])
        guard AccessStore.save([routine], to: name) else {
            throw XCTSkip("The Keychain is not available to this test host.")
        }
        defer { AccessStore.remove(name) }
        XCTAssertEqual(AccessStore.load([Routine].self, from: name), [routine])

        // What is on disk is not the plain JSON.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let file = base.appendingPathComponent("Accessibility").appendingPathComponent(name + ".sealed")
        let raw = try Data(contentsOf: file)
        XCTAssertNil(raw.range(of: Data("blue pill".utf8)))

        AccessStore.remove(name)
        XCTAssertNil(AccessStore.load([Routine].self, from: name))
    }

    // MARK: - Pixels and text

    func testTheCenterOfThePictureIsNamed() async throws {
        let bluePicture = try solid(UIColor(red: 0.05, green: 0.2, blue: 0.85, alpha: 1))
        let blue = await AccessVision.centerColors(in: bluePicture)
        XCTAssertEqual(blue.count, 24 * 24)
        XCTAssertEqual(ColorNamer.describe(blue).spoken, "It looks blue.")

        let redPicture = try solid(UIColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1))
        let red = await AccessVision.centerColors(in: redPicture)
        XCTAssertEqual(ColorNamer.describe(red).spoken, "It looks red.")

        let nothing = await AccessVision.centerColors(in: Data("not a picture".utf8))
        XCTAssertTrue(nothing.isEmpty)
    }

    func testTextIsReadWithItsPlaceMeasuredFromTheTop() async throws {
        let jpeg = try picture { bounds in
            UIColor.white.setFill()
            UIRectFill(bounds)
            let words = NSAttributedString(string: "EXIT", attributes: [
                .font: UIFont.boldSystemFont(ofSize: 120),
                .foregroundColor: UIColor.black,
            ])
            words.draw(at: CGPoint(x: 40, y: 30))
        }
        let fragments = await AccessVision.text(in: jpeg, corrected: false)
        guard let exit = fragments.first(where: { $0.text.uppercased().contains("EXIT") }) else {
            throw XCTSkip("Text recognition is not available in this simulator.")
        }
        // Drawn in the top left, so it must be reported in the top left.
        XCTAssertLessThan(exit.box.midY, 0.5)
        XCTAssertLessThan(exit.box.midX, 0.5)
        XCTAssertEqual(ReadingOrder.headline(fragments).first?.uppercased(), "EXIT")
    }

    func testTheDirectionTonesAreSoundTheSystemCanPlay() throws {
        for side in [Side.left, .ahead, .right] {
            let data = CueTone.wav(CueTone.samples(CueTone.segments(side: side, urgent: true)))
            let player = try AVAudioPlayer(data: data)
            XCTAssertGreaterThan(player.duration, 0.2)
            XCTAssertEqual(player.numberOfChannels, 1)
        }
    }

    // MARK: - Whole turns

    private func say(_ text: String, picture: Data? = nil) async -> String? {
        await AccessibilityCoordinator.shared.handle(text) { picture }
    }

    func testSentencesForTheAssistantAreLeftAlone() async {
        let weather = await say("what's the weather tomorrow")
        XCTAssertNil(weather)
        let bot = await say("ask Indy about the deploy")
        XCTAssertNil(bot)
        let yes = await say("yes")
        XCTAssertNil(yes, "A yes with no question waiting is not ours.")
    }

    func testHelpIsAnsweredOnThePhone() async {
        let help = await say("Jarvis, what can I say?")
        XCTAssertEqual(help, AccessHelp.spoken)
    }

    func testAColorQuestionIsAnsweredFromThePicture() async throws {
        let picture = try solid(UIColor(red: 0.05, green: 0.2, blue: 0.85, alpha: 1))
        let reply = await say("what color is this", picture: picture)
        XCTAssertEqual(reply, "It looks blue.")
    }

    func testNoPictureIsSaidPlainly() async {
        let reply = await say("read this")
        XCTAssertEqual(reply?.contains("couldn't get a picture"), true)
    }

    func testATaskIsWalkedThroughOneStepAtATime() async {
        let coordinator = AccessibilityCoordinator.shared
        let routine = Routine(name: "Kettle check", steps: ["Fill the kettle", "Switch it on"])
        coordinator.saveRoutine(routine)
        defer { coordinator.removeRoutine(routine) }

        let first = await say("start my kettle check routine")
        XCTAssertEqual(first?.contains("Step 1 of 2. Fill the kettle."), true)
        let again = await say("repeat")
        XCTAssertEqual(again, "Step 1 of 2. Fill the kettle.")
        let recall = await say("what was I doing")
        XCTAssertEqual(recall?.contains("You are doing Kettle check. Step 1 of 2: Fill the kettle."), true)
        let second = await say("next")
        XCTAssertEqual(second, "Step 2 of 2. Switch it on.")
        let done = await say("next")
        XCTAssertEqual(done, "That was the last step. Kettle check is done.")
        XCTAssertNil(coordinator.task)
        // With the task over, "next" means nothing to the suite again.
        let after = await say("next")
        XCTAssertNil(after)
    }

    func testDeletingARoutineWaitsForAYes() async {
        let coordinator = AccessibilityCoordinator.shared
        let routine = Routine(name: "Bins", steps: ["Take the bins out"])
        coordinator.saveRoutine(routine)
        defer { coordinator.removeRoutine(routine) }

        let question = await say("delete the bins routine")
        XCTAssertEqual(question, "Delete the Bins routine? Say yes or no.")
        let refused = await say("no")
        XCTAssertEqual(refused, "Okay, I won't.")
        XCTAssertTrue(coordinator.routines.contains(routine))

        _ = await say("delete the bins routine")
        let repeated = await say("what?")
        XCTAssertEqual(repeated, question)
        let agreed = await say("yes")
        XCTAssertEqual(agreed, "Deleted the Bins routine.")
        XCTAssertFalse(coordinator.routines.contains(routine))
    }

    func testAnUnansweredQuestionDoesNotSwallowTheNextCommand() async {
        let coordinator = AccessibilityCoordinator.shared
        let routine = Routine(name: "Plants", steps: ["Water the plants"])
        coordinator.saveRoutine(routine)
        defer { coordinator.removeRoutine(routine) }

        _ = await say("delete the plants routine")
        let help = await say("what can I say")
        XCTAssertEqual(help, AccessHelp.spoken)
        // The question was dropped, so a later yes deletes nothing.
        let yes = await say("yes")
        XCTAssertNil(yes)
        XCTAssertTrue(coordinator.routines.contains(routine))
    }

    func testAnnouncementsDoNotCountAsRepliesOnceARealReplyStarts() {
        let voice = TTSService.shared
        // Urgent, so it is spoken whatever the app was saying when the test began.
        voice.announce("Car ahead.", urgent: true)
        XCTAssertTrue(voice.announcing)
        voice.speak("Here is your answer.")
        XCTAssertFalse(voice.announcing)
        voice.stop()
    }
}
