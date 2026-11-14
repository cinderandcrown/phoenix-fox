// OpenVision - OpenClawProtocol.swift
// OpenClaw WebSocket protocol message types

import Foundation

// MARK: - Request/Response Types

/// OpenClaw WebSocket request frame
struct OpenClawRequest: Codable, Sendable {
    let type: String // "req"
    let id: String
    let method: String
    let params: [String: JSONValue]

    init(id: String, method: String, params: [String: Any] = [:]) {
        self.type = "req"
        self.id = id
        self.method = method
        self.params = params.mapValues(JSONValue.init(jsonObject:))
    }
}

/// OpenClaw WebSocket response frame
struct OpenClawResponse: Codable, Sendable {
    let type: String // "res"
    let id: String
    let ok: Bool
    let payload: [String: JSONValue]?
    let error: OpenClawError?
}

/// OpenClaw WebSocket event frame
struct OpenClawEvent: Codable, Sendable {
    let type: String // "event"
    let event: String
    let payload: [String: JSONValue]?
    let seq: Int?
}

/// OpenClaw error structure
struct OpenClawError: Codable, Sendable {
    let code: String?
    let message: String?
}

// MARK: - Message Content Types

/// Content types in OpenClaw messages
enum OpenClawContentType: String {
    case text
    case image
    case toolCall = "tool_call"
    case toolResult = "tool_result"
}

/// Image content for sending to OpenClaw
struct OpenClawImageContent {
    let mimeType: String
    let data: Data

    var base64Encoded: String {
        data.base64EncodedString()
    }

    init(jpegData: Data) {
        self.mimeType = "image/jpeg"
        self.data = jpegData
    }

    init(pngData: Data) {
        self.mimeType = "image/png"
        self.data = pngData
    }
}

// MARK: - Event Types

/// Known OpenClaw event types
enum OpenClawEventType: String {
    case agentMessage = "agent_message"
    case toolStatus = "tool_status"
    case runStarted = "run_started"
    case runCompleted = "run_completed"
    case error = "error"
}

// MARK: - Method Names

/// OpenClaw RPC method names
enum OpenClawMethod: String {
    case connect = "connect"
    case sendMessage = "chat.send"
    case cancelRun = "run/cancel"
    case toolResult = "tool.result"
}
