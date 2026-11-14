// SPDX-License-Identifier: Apache-2.0 AND MIT
// Derived from OpenVision (https://github.com/rayl15/OpenVision), MIT License,
// Copyright (c) 2026 OpenVision Contributors. Changes by Cinder and Crown LLC are
// licensed under Apache-2.0. See LICENSE, NOTICE, and THIRD_PARTY_NOTICES.md.
// Phoenix Fox - MainTabView.swift
// The three tabs: Home, History, Settings.

import SwiftUI

struct MainTabView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var conversationManager: ConversationManager

    // MARK: - State

    @State private var selectedTab: Tab = .home

    // MARK: - Tab Enum

    enum Tab: String, CaseIterable {
        case home = "Home"
        case history = "History"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .home: return "flame.fill"
            case .history: return "clock.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    // MARK: - Body

    // The tab bar is the system's own, so it is Liquid Glass on iOS 26 and follows light
    // and dark mode, Increase Contrast, and Reduce Transparency without any help from us.
    var body: some View {
        TabView(selection: $selectedTab) {
            VoiceAgentView()
                .tabItem {
                    Label(Tab.home.rawValue, systemImage: Tab.home.icon)
                }
                .tag(Tab.home)

            ConversationListView()
                .tabItem {
                    Label(Tab.history.rawValue, systemImage: Tab.history.icon)
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
    }
}

#Preview {
    MainTabView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
        .environmentObject(ConversationManager.shared)
}
