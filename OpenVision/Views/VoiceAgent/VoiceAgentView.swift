// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The home screen, connected to the running app.
//
// This view owns the voice pipeline's view model and forwards the state changes it needs
// (speech starting and stopping, the scene becoming active). What is drawn is `HomeContent`,
// from a `HomeModel` built here. Nothing in this file decides how anything looks.

import SwiftUI

struct VoiceAgentView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager

    // MARK: - ViewModel

    @StateObject private var viewModel = VoiceAgentViewModel()

    // MARK: - Observed services
    // Only the services whose @Published state the body reacts to directly. They are the same
    // singletons the ViewModel drives — observed here purely so onChange fires.

    @StateObject private var voiceCommandService = VoiceCommandService.shared
    @StateObject private var ttsService = TTSService.shared
    @StateObject private var kokoroTTS = KokoroTTSService.shared
    @StateObject private var grokTTS = CloudTTSService.grok
    @StateObject private var openAITTS = CloudTTSService.openAI
    @StateObject private var documentFocus = DocumentFocus.shared
    @ObservedObject private var companion = CompanionRuntime.shared
    @ObservedObject private var team = TeamBoardStore.shared
    @ObservedObject private var look = LookToTalk.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var sheet: HomeSheet? = nil

    // MARK: - Body

    var body: some View {
        // The team's "2 minutes ago" lines are worked out from the time, so the screen is
        // drawn again every ten seconds. Nothing else depends on the clock.
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            HomeContent(model: model(now: timeline.date), actions: actions)
        }
        .onAppear {
            viewModel.onAppear()
            team.sync(roster: settingsManager.settings.assistantBots)
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.foregrounded() }
        }
        .task {
            await viewModel.requestSpeechAuthorization()
        }
        // Observe TTS state changes
        .onChange(of: ttsService.isSpeaking) { _, isSpeaking in
            viewModel.ttsSpeakingChanged(isSpeaking)
        }
        .onChange(of: kokoroTTS.isSpeaking) { _, speaking in
            viewModel.neuralSpeakingChanged(speaking)
        }
        .onChange(of: grokTTS.isSpeaking) { _, speaking in
            viewModel.neuralSpeakingChanged(speaking)
        }
        .onChange(of: openAITTS.isSpeaking) { _, speaking in
            viewModel.neuralSpeakingChanged(speaking)
        }
        // Control thinking sound based on agent state
        .onChange(of: viewModel.agentState) { _, newState in
            viewModel.agentStateChanged(newState)
        }
        // Observe VoiceCommandService state changes
        .onChange(of: voiceCommandService.state) { _, newState in
            viewModel.voiceStateChanged(newState)
        }
        .onChange(of: settingsManager.settings.assistantBots) { _, bots in
            team.sync(roster: bots)
        }
        // Haptics: the beats of a turn, the camera coming on, an answer arriving, trouble.
        .onChange(of: phase) { old, new in
            HapticCue.cue(from: old, to: new)?.play()
        }
        .onChange(of: cameraOn) { old, new in
            HapticCue.cue(cameraWasOn: old, cameraIsOn: new)?.play()
        }
        .onChange(of: team.arrivals) { _, _ in
            if team.lastArrivalUrgent {
                HapticCue.urgent.play()
            } else if phase != .replying {
                HapticCue.arrived.play()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            if message != nil { HapticCue.trouble.play() }
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                Group {
                    switch sheet {
                    case .glasses: GlassesSettingsView()
                    case .assistants: OwnAssistantSettingsView()
                    case .brain: AIBackendSettingsView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { self.sheet = nil }
                    }
                }
            }
            .environmentObject(settingsManager)
            .environmentObject(glassesManager)
        }
    }

    // MARK: - What the screen shows

    private var cameraOn: Bool {
        glassesManager.isStreaming || companion.cameraLightOn
    }

    private var signals: LiveSignals {
        let settings = settingsManager.settings
        return LiveSignals(
            activity: VoiceActivity(viewModel.agentState),
            voiceReady: viewModel.isVoiceReady,
            wakeWordOn: settings.wakeWordEnabled,
            wakeWord: settings.wakeWord,
            cameraOn: cameraOn,
            askedAssistant: team.board.workingNames,
            tool: viewModel.currentToolName
        )
    }

    private var phase: LivePhase { LivePhase(signals) }

    private func model(now: Date) -> HomeModel {
        let settings = settingsManager.settings
        var model = HomeModel()
        model.signals = signals
        model.glasses = GlassesStatus(
            registered: glassesManager.isRegistered,
            devicesInReach: glassesManager.connectedDeviceCount,
            cameraOn: cameraOn
        )
        if settings.aiBackend != .ownAssistant {
            model.team = .brain(settings.backendDisplayName)
        } else if settings.isOwnAssistantConfigured {
            model.team = .members(team.board.members)
        } else {
            model.team = .connect
        }
        model.now = now
        model.heard = viewModel.userTranscript
        model.reply = viewModel.aiTranscript
        model.showsExchange = settings.showTranscripts
        if companion.cameraLightOn || !companion.caption.isEmpty || companion.holdsConversation {
            model.status = companion.statusLine
            model.caption = companion.caption
        }
        model.largeCaption = LiveCaptions.shared.isOn
        model.document = documentFocus.activeDocument?.title
        if look.status != .off {
            model.look = LookNote(title: look.status.title, symbol: look.status.symbol, name: look.status.name)
        }
        model.canRecord = glassesManager.isRegistered
        model.isRecording = viewModel.isRecording
        model.recordingNote = viewModel.recordingStatus
        model.trouble = viewModel.errorMessage
        model.offline = NetworkPath.shared.status == .offline
        model.needsGlassesRegister = !glassesManager.isRegistered
        model.reviewerDemo = ReviewerDemo.isEnabled()
        let audio = AudioSessionManager.shared
        model.speakingThrough = "Speaking through \(audio.destination.title)"
        return model
    }

    private var actions: HomeActions {
        HomeActions(
            stage: { viewModel.stageTapped($0) },
            glasses: { sheet = .glasses },
            record: { viewModel.toggleRecording() },
            closeDocument: { documentFocus.deactivate() },
            releaseLook: { look.stop() },
            dismissTrouble: { viewModel.errorMessage = nil },
            connectAssistants: { sheet = .assistants },
            chooseBrain: { sheet = .brain }
        )
    }
}

/// A settings screen opened from the home screen.
private enum HomeSheet: String, Identifiable {
    case glasses
    case assistants
    case brain

    var id: String { rawValue }
}

private extension VoiceActivity {
    init(_ state: VoiceAgentViewModel.AgentState) {
        switch state {
        case .idle: self = .idle
        case .connecting: self = .connecting
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .toolRunning: self = .usingTool
        case .speaking: self = .speaking
        case .liveVideo: self = .liveVideo
        }
    }
}

#Preview {
    VoiceAgentView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
}
