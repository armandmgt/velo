import HotwireNative
import UIKit

extension HotwireTab {
    static let dashboard = HotwireTab(
        title: "Tableau de bord",
        image: UIImage(systemName: "chart.bar")!,
        url: AppConfig.baseURL
    )

    static let activities = HotwireTab(
        title: "Activités",
        image: UIImage(systemName: "bicycle")!,
        url: AppConfig.baseURL.appendingPathComponent("activities")
    )

    static let plannedRoutes = HotwireTab(
        title: "Parcours",
        image: UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath")!,
        url: AppConfig.baseURL.appendingPathComponent("planned_routes")
    )

    static let all: [HotwireTab] = [.dashboard, .activities, .plannedRoutes]

    /// The `tab` identifiers the server's path-configuration tags each section
    /// with (see `ConfigurationsController::TAB_RULES`), index-aligned with
    /// `all`. Cross-tab routing (`SceneDelegate.handle`) maps a proposal's
    /// declared owning tab to the index to select.
    private static let names: [String] = ["dashboard", "activities", "planned_routes"]

    /// The index in `all` of the tab named `name`, or `nil` if unknown.
    static func index(named name: String) -> Int? {
        names.firstIndex(of: name)
    }
}
