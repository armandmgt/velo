import Foundation

/// The visibility a recording is uploaded as (#41, S13 — #66). Mirrors the
/// server's `Activity` visibility enum.
///
/// The `rawValue` is the authoritative `activity[visibility]` wire value. The
/// review screen lets the user choose before upload; it defaults to `.private`,
/// matching the server's column default (privacy-safe).
enum Visibility: String, CaseIterable {
    case `private`
    case shareable
    case `public`

    /// The default for a fresh recording — privacy-safe, matching the server.
    static let `default`: Visibility = .private

    /// French label, matching the web app's `fr.yml` `activity.visibility.*` strings.
    var displayName: String {
        switch self {
        case .private: "Privée"
        case .shareable: "Lien partageable"
        case .public: "Publique"
        }
    }
}
