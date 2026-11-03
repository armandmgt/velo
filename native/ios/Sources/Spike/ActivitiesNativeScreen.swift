// PROTOTYPE (native mixed-tabs spike, #8). Throwaway: a rough SwiftUI activity
// list that replaces the Hotwire `/activities` page and pushes Hotwire pages.
import HotwireNative
import SwiftUI
import UIKit

struct SpikeActivity: Decodable, Identifiable {
    let id: Int
    let name: String
    let sport: String
    let location: String
    let start_time: String
    let distance: Double?
    let duration_seconds: Int
    let url: URL
}

@Observable
final class SpikeActivitiesModel {
    var activities: [SpikeActivity] = []
    var error: String?
    var fetchCount = 0

    func load() async {
        let url = AppConfig.baseURL.appending(path: "activities.json")
        let headers = await withCheckedContinuation { continuation in
            WebSessionCookies.headerFields(for: url) { continuation.resume(returning: $0) }
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { error = "HTTP \(status)"; return }
            struct Payload: Decodable { let activities: [SpikeActivity] }
            activities = try JSONDecoder().decode(Payload.self, from: data).activities
            fetchCount += 1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SpikeActivitiesView: View {
    let model: SpikeActivitiesModel
    let open: (URL) -> Void

    var body: some View {
        List {
            Section {
                Text("Native list · fetch #\(model.fetchCount)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("spikeNativeMarker")
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("spikeError")
                }
            }
            ForEach(model.activities) { activity in
                Button { open(activity.url) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.name).font(.headline)
                        Text("\(activity.location) · \(String(format: "%.1f km", activity.distance ?? 0))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("spikeActivityRow")
            }
        }
        .refreshable { await model.load() }
    }
}

final class SpikeActivitiesViewController: UIHostingController<SpikeActivitiesView>, PathConfigurationIdentifiable {
    static let pathConfigurationIdentifier = "activities_native"

    private let model = SpikeActivitiesModel()

    init(navigator: Navigator) {
        let model = self.model
        super.init(rootView: SpikeActivitiesView(model: model) { [weak navigator] url in
            navigator?.route(url)
        })
        title = "Activités"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Refetch on every reveal: the native stand-in for Turbo Stream refreshes.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await model.load() }
    }
}
