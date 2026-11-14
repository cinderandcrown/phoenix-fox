// OpenVision - OpenVisionApp.swift
// App entry point. Receives the universal link the Meta AI app uses to return from registration.

import SwiftUI
import MWDATCore

@main
struct OpenVisionApp: App {
    // MARK: - State Objects

    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var glassesManager = GlassesManager.shared
    @StateObject private var conversationManager = ConversationManager.shared

    @UIApplicationDelegateAdaptor(PhoenixPushDelegate.self) private var pushDelegate

    // MARK: - App Storage

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // MARK: - Initialization

    init() {
        // Unit tests run inside this app. They need its code, not its services.
        guard !AppLaunch.isHostingTests else { return }
        // Show timer/alarm notifications even when the app is in the foreground.
        NotificationForegroundPresenter.shared.register()
        // Create the location manager on the main thread + warm the cache for contextual notes.
        LocationHelper.shared.prewarm()

        // Move the model store OUT of Caches before anything touches the hub. iOS may purge
        // Caches under storage pressure, which silently deleted downloaded model weights (the app
        // then re-downloaded ~GBs at "connecting…" time). Must run before any HubClient exists.
        GemmaLocalService.bootstrapModelStore()

        WearablesSDK.start()
        if let failure = WearablesSDK.failure {
            print("[OpenVisionApp] Glasses SDK did not start: \(failure)")
        }
        print("[OpenVisionApp] Initialized")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            if AppLaunch.isHostingTests {
                Color.clear
            } else {
                content
            }
        }
    }

    private var content: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
                    .environmentObject(settingsManager)
                    .environmentObject(glassesManager)
                    .environmentObject(conversationManager)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(settingsManager)
                    .environmentObject(glassesManager)
            }
        }
        .overlay(alignment: .top) {
            // Sound alerts for Deaf and hard-of-hearing wearers show over every screen.
            AccessBannerView()
        }
        .tint(Theme.accent)
        .task {
            // Telemetry settings persist, but the sink lives in memory — without this a
            // relaunch (or a jetsam kill during a model switch) silently stopped pushing.
            MetricsCollector.shared.restoreAtLaunch()
        }
        .onOpenURL { url in
            open(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { open(url) }
        }
        .alert(
            "Connect your glasses?",
            isPresented: Binding(
                get: { glassesManager.pendingRegistration != nil },
                set: { _ in }
            )
        ) {
            Button("Connect") {
                Task { await glassesManager.answerPendingRegistration(approve: true) }
            }
            Button("Not now", role: .cancel) {
                Task { await glassesManager.answerPendingRegistration(approve: false) }
            }
        } message: {
            Text("The Meta AI app is asking to connect your glasses to Phoenix Fox. Phoenix Fox uses the glasses camera and microphones only when you ask it to, and the capture light on the glasses is on whenever the camera is.")
        }
    }

    // MARK: - Incoming links

    /// Routes a universal link. The Meta AI app returns through `/dat` after registration
    /// or a permission prompt; that link goes to the glasses SDK and nowhere else.
    private func open(_ url: URL) {
        switch IncomingLink(url) {
        case .wearables(let callback):
            Task { await glassesManager.handleCallback(callback) }
        case .app, nil:
            break
        }
    }
}

/// How this process was started.
enum AppLaunch {
    /// True when Xcode launched the app only to host the unit-test bundle.
    static let isHostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
