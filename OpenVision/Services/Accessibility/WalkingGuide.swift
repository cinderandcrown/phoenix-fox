// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Turn-by-turn walking directions, spoken through the glasses.
//
// Apple Maps plans the route. RouteProgress decides what to say and when. This file only
// connects the two to the phone's location, which iOS marks with the location arrow for as
// long as guidance runs.

import CoreLocation
import Foundation
import MapKit
import UIKit

@MainActor
final class WalkingGuide: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = WalkingGuide()

    @Published private(set) var isActive = false
    @Published private(set) var destination = ""

    private let manager = CLLocationManager()
    private var progress: RouteProgress?
    private var lastFix: LocationFix?
    private var query = ""
    private var rerouting = false
    private var waitingForFix: [UUID: CheckedContinuation<LocationFix?, Never>] = [:]

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 3
    }

    /// Plans a walking route and starts guidance. Returns the first line to say.
    func start(to place: String) async -> String {
        guard let here = await currentFix() else { return noFix }
        guard let route = await Self.plan(to: place, from: here.coordinate) else {
            return "I couldn't find a walking route to \(place). Check the name, or try a street address."
        }
        query = place
        var progress = RouteProgress(route: route, metric: Locale.current.measurementSystem != .us)
        let first = progress.begin()
        self.progress = progress
        destination = route.destination
        isActive = true
        // Guidance has to keep speaking with the phone locked in a pocket.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        return first + " I'll say each turn before you reach it. This follows the map, not the pavement, so I can't see crossings or obstacles."
    }

    func stop() -> String {
        guard isActive else { return "No walking directions are running." }
        end()
        return "Walking directions stopped."
    }

    /// The next turn and how far it is, for "next turn".
    func status() -> String {
        guard isActive, let progress else { return "No walking directions are running. Say walk me to, then a place." }
        return progress.status(at: lastFix)
    }

    /// One sentence for "what was I doing?", or nil when no walk is in progress.
    var summary: String? {
        isActive ? "You are walking to \(destination)." : nil
    }

    /// The nearest address, for "where am I?".
    func whereAmI() async -> String {
        guard let fix = await currentFix() else { return noFix }
        guard let address = await Self.address(at: fix.coordinate) else {
            return "I have your location but couldn't look up the address. You may be offline."
        }
        return "You are near \(address)."
    }

    private func end() {
        isActive = false
        progress = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - Location

    /// Why there is no fix, in words the wearer can act on.
    private var noFix: String {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return "I need your location for that. Allow location for Phoenix Fox in the Settings app, then ask again."
        case .authorizedWhenInUse where UIApplication.shared.applicationState != .active:
            // iOS only lets an app begin using location from the background when it has
            // been allowed to always.
            return "I can't get your location while the phone is locked. Unlock it and open Phoenix Fox, then ask again. To start from a locked phone, set location for Phoenix Fox to Always in the Settings app."
        default:
            return "I couldn't get your location. Move somewhere with a clearer view of the sky and ask again."
        }
    }

    /// A current fix, asking for permission the first time. Nil when permission is refused
    /// or no fix arrives in time.
    private func currentFix() async -> LocationFix? {
        var patience = 10.0
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            // The wearer needs time to hear the system's question and answer it.
            manager.requestAlwaysAuthorization()
            patience = 30
        default:
            // A walk in progress already has a fix a few seconds old at most.
            if let lastFix, isActive { return lastFix }
            manager.requestLocation()
        }
        let id = UUID()
        let wait = patience
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            self?.waitingForFix.removeValue(forKey: id)?.resume(returning: nil)
        }
        return await withCheckedContinuation { waitingForFix[id] = $0 }
    }

    private func deliver(_ fix: LocationFix?) {
        let waiting = Array(waitingForFix.values)
        waitingForFix.removeAll()
        for continuation in waiting { continuation.resume(returning: fix) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            coordinate: Coordinate(location.coordinate.latitude, location.coordinate.longitude),
            accuracy: location.horizontalAccuracy,
            course: location.course >= 0 && location.speed > 0.3 ? location.course : nil
        )
        lastFix = fix
        deliver(fix)
        guard isActive, var progress else { return }
        let events = progress.update(fix)
        self.progress = progress
        for event in events { handle(event) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // "Unknown" means no fix yet and the system is still trying.
        if (error as? CLError)?.code == .locationUnknown { return }
        deliver(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus != .notDetermined {
            deliver(nil)
        }
    }

    private func handle(_ event: RouteEvent) {
        switch event {
        case .say(let line):
            speak(line)
        case .arrived(let line):
            speak(line)
            end()
        case .offRoute:
            guard !rerouting, let here = lastFix else { return }
            rerouting = true
            speak("You're off the route. Finding a new one.")
            let place = query
            Task { [weak self] in
                let route = await Self.plan(to: place, from: here.coordinate)
                guard let self else { return }
                self.rerouting = false
                guard self.isActive else { return }
                guard let route else {
                    self.speak("I couldn't find a new route. Stop somewhere safe and ask again.")
                    return
                }
                var progress = RouteProgress(route: route, metric: Locale.current.measurementSystem != .us)
                let first = progress.begin()
                self.progress = progress
                self.speak(first)
            }
        }
    }

    private func speak(_ line: String) {
        CompanionSurface.present(bot: "Directions", text: line) { TTSService.shared.announce($0, urgent: true) }
    }

    // MARK: - Map lookups, off the main actor, returning plain values

    private nonisolated static func plan(to place: String, from start: Coordinate) async -> WalkingRoute? {
        let origin = CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = place
        search.region = MKCoordinateRegion(center: origin, latitudinalMeters: 5_000, longitudinalMeters: 5_000)
        guard let item = try? await MKLocalSearch(request: search).start().mapItems.first else { return nil }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = item
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }

        var steps: [WalkingRoute.Step] = []
        for step in route.steps {
            let count = step.polyline.pointCount
            var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
            step.polyline.getCoordinates(&points, range: NSRange(location: 0, length: count))
            let path = points.map { Coordinate($0.latitude, $0.longitude) }
            let instruction = step.instructions.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            // The map's first step is often an empty "start here". Its path joins the next.
            if instruction.isEmpty {
                if steps.isEmpty { continue }
                steps[steps.count - 1].path.append(contentsOf: path)
            } else {
                steps.append(.init(instruction: instruction, path: path))
            }
        }
        guard !steps.isEmpty else { return nil }
        return WalkingRoute(destination: item.name ?? place, steps: steps)
    }

    private nonisolated static func address(at point: Coordinate) async -> String? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let street = [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, place.locality].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? place.name : parts.joined(separator: ", ")
    }
}
