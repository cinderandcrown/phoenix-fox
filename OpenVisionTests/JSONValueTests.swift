// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class JSONValueTests: XCTestCase {

    // MARK: - From JSONSerialization

    func testBooleansAndNumbersStayDistinct() {
        // JSONSerialization hands back NSNumber for both, and NSNumber(1) also casts to Bool.
        let parsed = JSONValue(jsonText: #"{"flag": true, "one": 1, "zero": 0, "off": false}"#)
        XCTAssertEqual(parsed?["flag"], .bool(true))
        XCTAssertEqual(parsed?["off"], .bool(false))
        XCTAssertEqual(parsed?["one"], .number(1))
        XCTAssertEqual(parsed?["zero"], .number(0))
    }

    func testNestedStructureRoundTrips() throws {
        let text = #"{"action":"add","when":{"hour":18,"tags":["a","b"],"note":null},"ratio":0.5}"#
        let value = try XCTUnwrap(JSONValue(jsonText: text))
        XCTAssertEqual(value["action"]?.stringValue, "add")
        XCTAssertEqual(value["when"]?["hour"]?.intValue, 18)
        XCTAssertEqual(value["when"]?["tags"]?.arrayValue, ["a", "b"])
        XCTAssertEqual(value["when"]?["note"], .null)
        XCTAssertEqual(value["ratio"]?.doubleValue, 0.5)

        let data = try JSONSerialization.data(withJSONObject: value.jsonObject, options: [.sortedKeys])
        let again = try XCTUnwrap(JSONValue(jsonText: String(decoding: data, as: UTF8.self)))
        XCTAssertEqual(again, value)
    }

    func testMalformedTextIsNil() {
        XCTAssertNil(JSONValue(jsonText: "{not json"))
        XCTAssertNil(JSONValue(jsonText: ""))
    }

    func testValuesThatAreNotJSONBecomeNull() {
        XCTAssertEqual(JSONValue(jsonObject: Date()), .null)
    }

    // MARK: - Tool arguments

    func testArgumentsFromText() {
        let args = ToolArguments(jsonText: #"{"title":"Call Sam","hour":17}"#)
        XCTAssertEqual(args["title"]?.stringValue, "Call Sam")
        XCTAssertEqual(args["hour"]?.intValue, 17)
    }

    func testArgumentsFromMissingOrWrongShapeAreEmpty() {
        XCTAssertTrue(ToolArguments(jsonText: nil).isEmpty)
        XCTAssertTrue(ToolArguments(jsonText: "[1,2,3]").isEmpty)
        XCTAssertTrue(ToolArguments(jsonText: "garbage").isEmpty)
        XCTAssertTrue(ToolArguments(jsonObject: nil).isEmpty)
        XCTAssertTrue(ToolArguments(jsonObject: "a string").isEmpty)
    }

    func testArgumentsFromSerializationObject() {
        let object: [String: Any] = ["seconds": 90, "label": "tea", "nested": ["k": true]]
        let args = ToolArguments(jsonObject: object)
        XCTAssertEqual(args["seconds"]?.intValue, 90)
        XCTAssertEqual(args["label"]?.stringValue, "tea")
        XCTAssertEqual(args["nested"]?["k"]?.boolValue, true)
    }

    // MARK: - Lenient integers

    func testIntegerCoercion() {
        XCTAssertEqual(JSONValue.number(5).intValue, 5)
        XCTAssertEqual(JSONValue.number(5.9).intValue, 5)
        XCTAssertEqual(JSONValue.string(" 42 ").intValue, 42)
        XCTAssertNil(JSONValue.string("soon").intValue)
        XCTAssertNil(JSONValue.bool(true).intValue)
        XCTAssertNil(JSONValue.number(.infinity).intValue)
        XCTAssertNil(JSONValue.number(.nan).intValue)
        XCTAssertNil(JSONValue.number(1e300).intValue)
    }

    // MARK: - Literals and output shape

    func testLiteralsBuildTheExpectedTree() {
        let schema: JSONValue = [
            "type": "object",
            "properties": ["seconds": ["type": "integer"]],
            "required": ["seconds"],
            "strict": true,
            "weight": 0.5,
        ]
        XCTAssertEqual(schema["type"], .string("object"))
        XCTAssertEqual(schema["properties"]?["seconds"]?["type"], .string("integer"))
        XCTAssertEqual(schema["required"], .array([.string("seconds")]))
        XCTAssertEqual(schema["strict"], .bool(true))
        XCTAssertEqual(schema["weight"], .number(0.5))
    }

    func testWholeNumbersSerializeAsIntegers() throws {
        let value: JSONValue = ["count": 60, "ratio": 0.25]
        let data = try JSONSerialization.data(withJSONObject: value.jsonObject, options: [.sortedKeys])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"count":60,"ratio":0.25}"#)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let value: JSONValue = ["id": "a1", "ok": true, "items": [1, "two", .null, ["deep": 3.5]]]
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }

    func testDecodingKeepsBooleansApartFromNumbers() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":1,"b":true}"#.utf8))
        XCTAssertEqual(decoded["a"], .number(1))
        XCTAssertEqual(decoded["b"], .bool(true))
    }
}
