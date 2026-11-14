// SPDX-License-Identifier: Apache-2.0 AND MIT
// Derived from OpenVision (https://github.com/rayl15/OpenVision), MIT License,
// Copyright (c) 2026 OpenVision Contributors. Changes by Cinder and Crown LLC are
// licensed under Apache-2.0. See LICENSE, NOTICE, and THIRD_PARTY_NOTICES.md.
// OpenVision - ClipboardTool.swift
import Foundation
import UIKit

/// Copy text to the device clipboard so the user can paste it elsewhere.
struct ClipboardTool: NativeTool {
    let name = "copy_to_clipboard"
    let description = "Copy text to the clipboard. Use when the user says 'copy that' or wants a result saved to paste elsewhere."
    let parametersSchema: JSONValue = [
        "type": "object",
        "properties": ["text": ["type": "string", "description": "The text to copy"]],
        "required": ["text"]
    ]

    func execute(args: ToolArguments) async throws -> String {
        guard let text = args["text"]?.stringValue, !text.isEmpty else { return "There's nothing to copy." }
        await MainActor.run { UIPasteboard.general.string = text }
        let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
        return "Copied to clipboard: \(preview)"
    }
}
