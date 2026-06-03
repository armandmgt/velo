import Foundation

/// Central place for the server endpoints the app talks to.
///
/// In DEBUG builds we point at the local Rails dev server (`bin/dev`). The iOS
/// Simulator shares the host's network, so `localhost:3000` resolves directly.
/// Release builds target production.
enum AppConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:3000")!
    #else
    static let baseURL = URL(string: "https://velo.armandmgt.fr")!
    #endif

    /// Remote Hotwire Native path configuration (served by ConfigurationsController).
    static var pathConfigurationURL: URL {
        baseURL.appending(path: "configurations/ios_v1")
    }
}
