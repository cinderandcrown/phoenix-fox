// SPDX-License-Identifier: Apache-2.0 AND MIT
// Derived from OpenVision (https://github.com/rayl15/OpenVision), MIT License,
// Copyright (c) 2026 OpenVision Contributors. Changes by Cinder and Crown LLC are
// licensed under Apache-2.0. See LICENSE, NOTICE, and THIRD_PARTY_NOTICES.md.
// OpenVision - AppleNativeTools.swift
// Bridges the productivity NativeTools into Apple's Foundation Models tool-calling.
//
// Apple's `Tool` protocol wants a typed `@Generable` Arguments struct (not our [String: Any] schema),
// so we write one thin wrapper per tool — but each just forwards to the shared NativeToolRegistry, so
// all the real work (EventKit, notifications, location, clipboard) lives in one place.

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum AppleNativeTools {
    /// All native tools, ready to hand to a LanguageModelSession.
    static var all: [any Tool] {
        [AppleTimerTool(), ApplePomodoroTool(), AppleReminderTool(),
         AppleCalendarTool(), AppleNoteTool(), AppleClipboardTool(), AppleDocsTool()]
    }

    /// Run a native tool by name with a cleaned-up arg dict (drops empty strings / zeros meaning "unset").
    static func run(_ name: String, _ args: ToolArguments) async -> String {
        await NativeToolRegistry.shared.execute(name: name, args: args)
    }
}

@available(iOS 26.0, *)
struct AppleTimerTool: Tool {
    let name = "set_timer"
    let description = "Set a countdown timer that alerts after a duration. For 'set a 10 minute timer', 'timer for the pasta'."
    @Generable struct Arguments {
        @Guide(description: "Duration in seconds") let seconds: Int
        @Guide(description: "Optional label, e.g. 'pasta'. Empty if none.") let label: String
    }
    func call(arguments: Arguments) async throws -> String {
        var args: ToolArguments = ["seconds": JSONValue(arguments.seconds)]
        if !arguments.label.isEmpty { args["label"] = JSONValue(arguments.label) }
        return await AppleNativeTools.run(name, args)
    }
}

@available(iOS 26.0, *)
struct ApplePomodoroTool: Tool {
    let name = "start_pomodoro"
    let description = "Start a Pomodoro focus session (a work block then a break). Defaults: 25 min work, 5 min break — pass 0 to use a default."
    @Generable struct Arguments {
        @Guide(description: "Focus minutes, or 0 for default (25)") let work_minutes: Int
        @Guide(description: "Break minutes, or 0 for default (5)") let break_minutes: Int
    }
    func call(arguments: Arguments) async throws -> String {
        var args: ToolArguments = [:]
        if arguments.work_minutes > 0 { args["work_minutes"] = JSONValue(arguments.work_minutes) }
        if arguments.break_minutes > 0 { args["break_minutes"] = JSONValue(arguments.break_minutes) }
        return await AppleNativeTools.run(name, args)
    }
}

@available(iOS 26.0, *)
struct AppleReminderTool: Tool {
    let name = "create_reminder"
    let description = "Create a reminder in Apple Reminders, optionally with a due time."
    @Generable struct Arguments {
        @Guide(description: "What to be reminded about") let title: String
        @Guide(description: "For a clock time like '6pm': the hour in 24-hour form (0-23), or -1 if none. USE THIS for any time of day.") let hour: Int
        @Guide(description: "Minute 0-59 (with hour). 0 if none.") let minute: Int
        @Guide(description: "With hour: 0=today, 1=tomorrow, 2=in two days.") let day_offset: Int
        @Guide(description: "Due this many minutes from now, or 0. ONLY for 'in N minutes', never a clock time.") let minutes_from_now: Int
    }
    func call(arguments: Arguments) async throws -> String {
        var args: ToolArguments = ["title": JSONValue(arguments.title)]
        if (0...23).contains(arguments.hour) {
            args["hour"] = JSONValue(arguments.hour)
            args["minute"] = JSONValue(arguments.minute)
            args["day_offset"] = JSONValue(arguments.day_offset)
        } else if arguments.minutes_from_now > 0 {
            args["minutes_from_now"] = JSONValue(arguments.minutes_from_now)
        }
        return await AppleNativeTools.run(name, args)
    }
}

@available(iOS 26.0, *)
struct AppleCalendarTool: Tool {
    let name = "calendar"
    let description = "Read or add calendar events. action 'today', 'upcoming', or 'add' (add needs title and start_iso8601)."
    @Generable struct Arguments {
        @Guide(description: "today, upcoming, or add") let action: String
        @Guide(description: "Event title (for add). Empty otherwise.") let title: String
        @Guide(description: "For add at a clock time like '3pm': the hour in 24-hour form (0-23), or -1 if none. USE THIS for any time of day.") let hour: Int
        @Guide(description: "Minute 0-59 (with hour). 0 if none.") let minute: Int
        @Guide(description: "With hour: 0=today, 1=tomorrow, 2=in two days.") let day_offset: Int
        @Guide(description: "For add: minutes from now, or 0. ONLY for 'in N minutes', never a clock time.") let minutes_from_now: Int
        @Guide(description: "Length in minutes (for add), or 0 for default") let duration_minutes: Int
    }
    func call(arguments: Arguments) async throws -> String {
        var args: ToolArguments = ["action": JSONValue(arguments.action)]
        if !arguments.title.isEmpty { args["title"] = JSONValue(arguments.title) }
        if (0...23).contains(arguments.hour) {
            args["hour"] = JSONValue(arguments.hour)
            args["minute"] = JSONValue(arguments.minute)
            args["day_offset"] = JSONValue(arguments.day_offset)
        } else if arguments.minutes_from_now > 0 {
            args["minutes_from_now"] = JSONValue(arguments.minutes_from_now)
        }
        if arguments.duration_minutes > 0 { args["duration_minutes"] = JSONValue(arguments.duration_minutes) }
        return await AppleNativeTools.run(name, args)
    }
}

@available(iOS 26.0, *)
struct AppleNoteTool: Tool {
    let name = "note"
    let description = "Save, search, list, or delete quick notes (auto-tagged with location + time). save needs content; search/delete need query."
    @Generable struct Arguments {
        @Guide(description: "save, search, list, or delete") let action: String
        @Guide(description: "Note text (for save). Empty otherwise.") let content: String
        @Guide(description: "Comma-separated tags (for save, optional)") let tags: String
        @Guide(description: "Keyword (for search/delete). Empty otherwise.") let query: String
    }
    func call(arguments: Arguments) async throws -> String {
        var args: ToolArguments = ["action": JSONValue(arguments.action)]
        if !arguments.content.isEmpty { args["content"] = JSONValue(arguments.content) }
        if !arguments.tags.isEmpty { args["tags"] = JSONValue(arguments.tags) }
        if !arguments.query.isEmpty { args["query"] = JSONValue(arguments.query) }
        return await AppleNativeTools.run(name, args)
    }
}

@available(iOS 26.0, *)
struct AppleClipboardTool: Tool {
    let name = "copy_to_clipboard"
    let description = "Copy text to the clipboard. For 'copy that'."
    @Generable struct Arguments {
        @Guide(description: "The text to copy") let text: String
    }
    func call(arguments: Arguments) async throws -> String {
        await AppleNativeTools.run(name, ["text": JSONValue(arguments.text)])
    }
}

@available(iOS 26.0, *)
struct AppleDocsTool: Tool {
    let name = "search_docs"
    let description = "Work with the user's imported documents (manuals, recipes, guides). search: find relevant passages (use when asked about their documents). list: name the documents. focus: user wants to work with one document ('open my router manual') — it will then be checked first for every question. unfocus: user is done ('close the document')."
    @Generable struct Arguments {
        @Guide(description: "search, list, focus, or unfocus") let action: String
        @Guide(description: "What to look for (search), or the document name (focus). Empty otherwise.") let query: String
    }
    func call(arguments: Arguments) async throws -> String {
        var args: ToolArguments = ["action": JSONValue(arguments.action)]
        if !arguments.query.isEmpty { args["query"] = JSONValue(arguments.query) }
        return await AppleNativeTools.run(name, args)
    }
}
#endif
