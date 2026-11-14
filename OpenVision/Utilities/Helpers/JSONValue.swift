// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// A JSON document as a value type.
///
/// Model tool calls arrive as untyped JSON. `[String: Any]` cannot cross isolation
/// domains, so tool arguments and schemas are carried as `JSONValue`, which is
/// `Sendable`, comparable in tests, and still written with ordinary literals.
enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Building

extension JSONValue {
    init(_ value: Int) { self = .number(Double(value)) }
    init(_ value: Double) { self = .number(value) }
    init(_ value: Bool) { self = .bool(value) }
    init(_ value: String) { self = .string(value) }

    /// Converts what `JSONSerialization` produces. Values that are not JSON become `null`.
    init(jsonObject: Any) {
        switch jsonObject {
        case let value as JSONValue:
            self = value
        case let text as String:
            self = .string(text)
        case let number as NSNumber:
            // NSNumber also answers `as? Bool` for 0 and 1, so ask Core Foundation which it is.
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let items as [Any]:
            self = .array(items.map(JSONValue.init(jsonObject:)))
        case let fields as [String: Any]:
            self = .object(fields.mapValues(JSONValue.init(jsonObject:)))
        default:
            self = .null
        }
    }

    /// Parses JSON text. Returns nil when the text is not valid JSON.
    init?(jsonText: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8), options: [.fragmentsAllowed]) else {
            return nil
        }
        self.init(jsonObject: object)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// A tool-call argument object. Anything that is not a JSON object becomes empty.
    init(jsonObject: Any?) {
        guard let jsonObject, case .object(let fields) = JSONValue(jsonObject: jsonObject) else {
            self = [:]
            return
        }
        self = fields
    }

    /// Parses a tool call's `arguments` string. Missing or malformed text becomes empty.
    init(jsonText: String?) {
        guard let jsonText, case .object(let fields)? = JSONValue(jsonText: jsonText) else {
            self = [:]
            return
        }
        self = fields
    }
}

// MARK: - Reading

extension JSONValue {
    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let flag) = self { return flag }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .number(let number): return number
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Models send integers as numbers, as decimals, and as strings. All three read as an Int.
    var intValue: Int? {
        switch self {
        case .number(let number):
            guard number.isFinite, abs(number) < 9.0e15 else { return nil }
            return Int(number)
        case .string(let text):
            return Int(text.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }

    var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// The shape `JSONSerialization` writes. Whole numbers are emitted as integers so a
    /// schema or an argument reads `60`, not `60.0`.
    var jsonObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .number(let number):
            if number.isFinite, number == number.rounded(), abs(number) < 9.0e15 { return Int(number) }
            return number
        case .string(let text): return text
        case .array(let items): return items.map(\.jsonObject)
        case .object(let fields): return fields.mapValues(\.jsonObject)
        }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let items = try? container.decode([JSONValue].self) {
            self = .array(items)
        } else if let fields = try? container.decode([String: JSONValue].self) {
            self = .object(fields)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let flag): try container.encode(flag)
        case .number(let number): try container.encode(number)
        case .string(let text): try container.encode(text)
        case .array(let items): try container.encode(items)
        case .object(let fields): try container.encode(fields)
        }
    }
}
