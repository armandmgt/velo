import Foundation

/// The sport a recording is uploaded as.
///
/// The `rawValue` is the authoritative `activity[sport]` wire value (one of the
/// 14 `Activity` enum cases on the server). `gpxType` is the best-effort
/// `<trk><type>` we also emit into the GPX for self-containedness — the param
/// wins server-side, and `workout` has no GPX mapping at all, so it must travel
/// via the param alone.
enum Sport: String, CaseIterable {
    case bike
    case mountainBikeRide = "mountain_bike_ride"
    case gravelRide = "gravel_ride"
    case virtualRide = "virtual_ride"
    case eBikeRide = "e_bike_ride"
    case run
    case trailRun = "trail_run"
    case virtualRun = "virtual_run"
    case walk
    case hike
    case alpineSki = "alpine_ski"
    case nordicSki = "nordic_ski"
    case swim
    case workout

    /// French label, matching the web app's `fr.yml` `activity.sport.*` strings.
    var displayName: String {
        switch self {
        case .bike: "Vélo de route"
        case .mountainBikeRide: "VTT"
        case .gravelRide: "Gravel"
        case .virtualRide: "Vélo virtuel"
        case .eBikeRide: "Vélo électrique"
        case .run: "Course à pied"
        case .trailRun: "Trail"
        case .virtualRun: "Course virtuelle"
        case .walk: "Marche"
        case .hike: "Randonnée"
        case .alpineSki: "Ski alpin"
        case .nordicSki: "Ski de fond"
        case .swim: "Natation"
        case .workout: "Entraînement"
        }
    }

    /// How the sport's live metrics read, mirroring the server's
    /// `Activity::SPORT_CATEGORY`. Drives whether the recording screen shows
    /// **speed** (km/h) or **pace** (min/km).
    enum Category {
        case cycling
        case running
        case other
    }

    var category: Category {
        switch self {
        case .bike, .mountainBikeRide, .gravelRide, .virtualRide, .eBikeRide: .cycling
        case .run, .trailRun, .virtualRun, .walk: .running
        case .hike, .alpineSki, .nordicSki, .swim, .workout: .other
        }
    }

    /// Running-style sports read as pace (min/km); everything else as speed (km/h).
    var usesPace: Bool { category == .running }

    /// SF Symbol shown in the picker.
    var symbolName: String {
        switch self {
        case .bike, .gravelRide, .eBikeRide: "bicycle"
        case .mountainBikeRide: "figure.outdoor.cycle"
        case .virtualRide: "figure.indoor.cycle"
        case .run, .trailRun, .virtualRun: "figure.run"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .alpineSki: "figure.skiing.downhill"
        case .nordicSki: "figure.skiing.crosscountry"
        case .swim: "figure.pool.swim"
        case .workout: "figure.strengthtraining.traditional"
        }
    }

    /// Best-effort `<trk><type>` to emit; `nil` when there is no GPX mapping
    /// (`workout`), in which case we rely solely on the `activity[sport]` param.
    var gpxType: String? {
        switch self {
        case .bike: "cycling"
        case .mountainBikeRide: "mountainbiking"
        case .gravelRide: "gravelbiking"
        case .virtualRide: "virtualride"
        case .eBikeRide: "ebiking"
        case .run: "running"
        case .trailRun: "trailrunning"
        case .virtualRun: "virtualrunning"
        case .walk: "walking"
        case .hike: "hiking"
        case .alpineSki: "alpineski"
        case .nordicSki: "nordicski"
        case .swim: "swimming"
        case .workout: nil
        }
    }

    // MARK: - Last-used persistence

    private static let lastUsedKey = "recording.lastUsedSport"

    /// The sport chosen for the previous recording, so the picker defaults to it.
    /// Falls back to `.bike` on first run or an unknown stored value.
    static var lastUsed: Sport {
        get {
            guard let raw = UserDefaults.standard.string(forKey: lastUsedKey),
                  let sport = Sport(rawValue: raw) else { return .bike }
            return sport
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastUsedKey) }
    }
}
