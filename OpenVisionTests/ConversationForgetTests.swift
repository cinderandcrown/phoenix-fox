// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

/// A turn about the wearer's health is taken back out of the conversation history.
final class ConversationForgetTests: XCTestCase {
    func testTheLastSentenceIsTakenBackAndTheTitleWithIt() {
        var conversation = Conversation()
        conversation.addMessage(.user("log a dose of ibuprofen"))
        XCTAssertEqual(conversation.title, "log a dose of ibuprofen")

        XCTAssertTrue(conversation.forgetLastUserMessage(saying: "log a dose of ibuprofen"))
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertEqual(conversation.title, "New Conversation")
    }

    func testAnEarlierTitleIsKept() {
        var conversation = Conversation()
        conversation.addMessage(.user("what's the weather"))
        conversation.addMessage(.assistant("Sunny."))
        conversation.addMessage(.user("did I take my ibuprofen"))

        XCTAssertTrue(conversation.forgetLastUserMessage(saying: "did I take my ibuprofen"))
        XCTAssertEqual(conversation.messages.map(\.content), ["what's the weather", "Sunny."])
        XCTAssertEqual(conversation.title, "what's the weather")
    }

    func testNothingElseIsEverRemoved() {
        var conversation = Conversation()
        conversation.addMessage(.user("check the ingredients"))
        conversation.addMessage(.assistant("I found milk."))

        // The last message is the assistant's, so nothing is taken back.
        XCTAssertFalse(conversation.forgetLastUserMessage(saying: "check the ingredients"))
        // A different sentence is not taken back either.
        conversation.addMessage(.user("what time is it"))
        XCTAssertFalse(conversation.forgetLastUserMessage(saying: "check the ingredients"))
        XCTAssertEqual(conversation.messages.count, 3)
    }
}
