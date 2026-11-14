// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Minimal CameraAccess-sample sequence for on-device diagnosis. Does not use
// GlassesManager / GlassesControlSession. Logs every step to GlassesLink.

import Foundation
import MWDATCamera
import MWDATCore

@MainActor
enum CameraAccessParity {
    /// Runs the official sample order: AutoDeviceSelector → createSession → start →
    /// (wait .started) → checkPermission → optional requestPermission → addCamera → stream.start.
    /// Stops the stream/session before returning. Returns a multi-line report.
    static func runProbe(startStream: Bool = true) async -> String {
        var lines: [String] = ["CameraAccess parity probe"]
        func log(_ line: String) {
            lines.append(line)
            GlassesLink.shared.record("Parity: \(line)")
        }

        guard let wearables = WearablesSDK.interface else {
            log("FAIL: WearablesSDK not running — \(WearablesSDK.failure ?? "unknown")")
            return lines.joined(separator: "\n")
        }

        let devices = wearables.devices
        log("devices listed: \(devices.count)")
        for id in devices {
            if let device = wearables.deviceForIdentifier(id) {
                log("  \(device.nameOrId()) link=\(device.linkState) compat=\(device.compatibility()) type=\(device.deviceType())")
            } else {
                log("  \(id) (deviceForIdentifier nil)")
            }
        }

        let selector = AutoDeviceSelector(wearables: wearables)
        log("AutoDeviceSelector.activeDevice=\(String(describing: selector.activeDevice))")

        let session: DeviceSession
        do {
            session = try wearables.createSession(deviceSelector: selector)
            log("createSession OK")
        } catch {
            log("FAIL createSession: \(error.localizedDescription)")
            return lines.joined(separator: "\n")
        }

        let states = session.stateStream()
        do {
            try session.start()
            log("session.start() returned")
        } catch {
            log("FAIL session.start(): \(error.localizedDescription)")
            session.stop()
            return lines.joined(separator: "\n")
        }

        let started = await waitStarted(states: states, seconds: 20)
        log("session state after wait: started=\(started) current=\(session.state)")
        if let device = session.device {
            log("session.device link=\(device.linkState) name=\(device.nameOrId())")
        } else {
            log("session.device nil")
        }

        guard started else {
            session.stop()
            log("FAIL: session never reached .started")
            return lines.joined(separator: "\n")
        }

        do {
            var status = try await wearables.checkPermissionStatus(.camera)
            log("checkPermissionStatus(.camera)=\(status)")
            if status != .granted {
                status = try await wearables.requestPermission(.camera)
                log("requestPermission(.camera)=\(status)")
            }
            guard status == .granted else {
                session.stop()
                log("FAIL: camera permission not granted")
                return lines.joined(separator: "\n")
            }
        } catch {
            session.stop()
            log("FAIL permission: \(error.localizedDescription)")
            return lines.joined(separator: "\n")
        }

        guard startStream else {
            session.stop()
            log("OK up to permission (stream skipped)")
            return lines.joined(separator: "\n")
        }

        // Same baseline shape as a standard look (raw frames, medium, 7 fps).
        let config = StreamConfiguration(
            videoCodec: .raw,
            audioCodec: nil,
            resolution: .medium,
            frameRate: 7
        )
        do {
            guard let camera = try session.addCamera(config: config) else {
                session.stop()
                log("FAIL: addCamera returned nil")
                return lines.joined(separator: "\n")
            }
            log("addCamera OK; starting stream")
            camera.stream.start()
            try? await Task.sleep(for: .seconds(2))
            log("stream.state=\(camera.stream.state)")
            camera.stop()
            log("camera.stop()")
        } catch {
            log("FAIL addCamera/stream: \(error.localizedDescription)")
        }

        session.stop()
        log("session.stop(); probe done")
        return lines.joined(separator: "\n")
    }

    private static func waitStarted(states: AsyncStream<DeviceSessionState>, seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in states {
                    if state == .started { return true }
                    if state == .stopped { return false }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
