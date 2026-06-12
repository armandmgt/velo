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

    static let all: [HotwireTab] = [.dashboard, .activities]
}
