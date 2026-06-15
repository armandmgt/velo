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
}
