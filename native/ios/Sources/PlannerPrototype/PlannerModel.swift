// PROTOTYPE — throwaway native route planner spike (wayfinder #21, branch
// prototype/native-route-planner). Not production code: no tests, minimal errors.
import CoreLocation
import Foundation
import Observation

enum HandleStyle: String, CaseIterable, Identifiable { case overlay = "Poignées app", sdk = "Annotations SDK"; var id: Self { self } }
enum SheetStyle: String, CaseIterable, Identifiable { case detents = "Feuille à crans", card = "Carte flottante"; var id: Self { self } }
enum InsertStyle: String, CaseIterable, Identifiable { case drag = "Glisser la ligne", tap = "Toucher la ligne"; var id: Self { self } }

struct Coord: Equatable {
    var lng: Double
    var lat: Double
    var cl: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
    init(lng: Double, lat: Double) { self.lng = lng; self.lat = lat }
    init(_ c: CLLocationCoordinate2D) { lng = c.longitude; lat = c.latitude }
    var pair: [Double] { [lng, lat] }
}

/// A gesture in flight: either a waypoint being dragged or a new one being pulled
/// out of the route line. Drawn as a dashed rubber band until release.
struct DragPreview: Equatable {
    var movingIndex: Int?
    var insertAt: Int?
    var coordinate: Coord
}

@Observable
final class PlannerModel {
    var handleStyle: HandleStyle = .overlay
    var sheetStyle: SheetStyle = .detents
    var insertStyle: InsertStyle = .drag

    private(set) var waypoints: [Coord] = []
    private(set) var route: [Coord] = []
    private(set) var distanceMeters: Double?
    private(set) var elevationGainMeters: Double?
    private(set) var elevationSamples: [(Double, Double)] = []
    var name = ""
    var sport = "bike" { didSet { if sport != oldValue { schedulePreview() } } }
    var selectedIndex: Int?
    var dragPreview: DragPreview?
    var pendingFit = false
    private(set) var isRouting = false
    var error: String?
    private(set) var lastAction = "—"
    private(set) var previewCount = 0

    private var history: [[Coord]] = []
    private var future: [[Coord]] = []
    private var previewTask: Task<Void, Never>?

    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    static let sports: [(String, String)] = [
        ("bike", "Vélo"), ("gravel_ride", "Gravel"), ("mountain_bike_ride", "VTT"), ("e_bike_ride", "VAE"),
        ("run", "Course"), ("trail_run", "Trail"), ("walk", "Marche"), ("hike", "Randonnée"),
    ]

    // MARK: Edits — every one goes through `set` so undo covers them all.

    func add(_ c: Coord) { set(waypoints + [c], "ajout #\(waypoints.count + 1)") }

    func move(_ i: Int, to c: Coord) {
        guard waypoints.indices.contains(i) else { return }
        var next = waypoints; next[i] = c
        set(next, "déplacement #\(i + 1)")
    }

    func insert(at i: Int, _ c: Coord) {
        var next = waypoints; next.insert(c, at: min(max(i, 0), next.count))
        set(next, "insertion #\(i + 1)")
        selectedIndex = nil
    }

    func remove(_ i: Int) {
        guard waypoints.indices.contains(i) else { return }
        var next = waypoints; next.remove(at: i)
        set(next, "suppression #\(i + 1)")
        selectedIndex = nil
    }

    func replaceAll(_ next: [Coord], _ action: String) { set(next, action) }

    func clear() { set([], "effacer") }

    func undo() {
        guard let prev = history.popLast() else { return }
        future.append(waypoints)
        apply(prev, "annuler")
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(waypoints)
        apply(next, "rétablir")
    }

    private func set(_ next: [Coord], _ action: String) {
        guard next != waypoints else { return }
        history.append(waypoints)
        future.removeAll()
        apply(next, action)
    }

    private func apply(_ next: [Coord], _ action: String) {
        waypoints = next
        lastAction = action
        if let s = selectedIndex, !next.indices.contains(s) { selectedIndex = nil }
        schedulePreview()
    }

    // MARK: Insertion slot — ported from route_planner_controller.js

    /// Bracket the touched route index between the route indices nearest to each
    /// waypoint; that's where the new waypoint goes.
    func insertionIndex(for c: Coord) -> Int {
        guard route.count >= 2 else { return waypoints.count }
        let hit = nearestRouteIndex(c)
        let indices = waypoints.map(nearestRouteIndex)
        for i in 0..<max(indices.count - 1, 0) where hit >= indices[i] && hit <= indices[i + 1] {
            return i + 1
        }
        return waypoints.count
    }

    private func nearestRouteIndex(_ c: Coord) -> Int {
        var best = 0, bestD = Double.infinity
        for (i, r) in route.enumerated() {
            let d = (r.lng - c.lng) * (r.lng - c.lng) + (r.lat - c.lat) * (r.lat - c.lat)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    // MARK: Routing

    private func schedulePreview() {
        previewTask?.cancel()
        guard waypoints.count >= 2 else {
            route = []; distanceMeters = nil; elevationGainMeters = nil; elevationSamples = []
            return
        }
        let body = (sport, waypoints)
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.isRouting = true
            defer { self.isRouting = false }
            do {
                let result = try await PlannerAPI.preview(sport: body.0, waypoints: body.1)
                guard !Task.isCancelled else { return }
                self.route = result.coordinates
                self.distanceMeters = result.distanceMeters
                self.elevationGainMeters = result.elevationGainMeters
                self.elevationSamples = result.elevationSamples
                self.error = nil
                self.previewCount += 1
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "\(error)"
            }
        }
    }

    func importGpx(_ url: URL) async {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let result = try await PlannerAPI.importGpx(data: data, filename: url.lastPathComponent)
            if name.isEmpty, let n = result.name { name = n }
            pendingFit = true
            replaceAll(result.waypoints, "import GPX (\(result.waypoints.count) pts)")
        } catch {
            self.error = "\(error)"
        }
    }

    func save() async -> URL? {
        do {
            return try await PlannerAPI.save(name: name.isEmpty ? "Itinéraire" : name, sport: sport, waypoints: waypoints)
        } catch {
            self.error = "\(error)"
            return nil
        }
    }

    var stateLine: String {
        "\(waypoints.count) pts · \(route.count) seg · sel \(selectedIndex.map { "#\($0 + 1)" } ?? "—") · \(lastAction) · \(isRouting ? "routage…" : "ok #\(previewCount)")"
    }
}
