// PROTOTYPE (app-owned tabs spike, #11). Throwaway: a SwiftUI `TabView` owns the
// tab bar; each tab hosts a Hotwire `Navigator`. Replaces `RecordTabBarController`.
import HotwireNative
import SwiftUI
import UIKit

@Observable
final class AppTabsModel {
    struct TabSpec {
        let name: String
        let title: String
        let systemImage: String
        let url: URL
    }

    static let specs: [TabSpec] = [
        .init(name: "dashboard", title: "Tableau de bord", systemImage: "chart.bar", url: AppConfig.baseURL),
        .init(name: "activities", title: "Activités", systemImage: "bicycle",
              url: AppConfig.baseURL.appendingPathComponent("activities")),
        .init(name: "planned_routes", title: "Parcours",
              systemImage: "point.topleft.down.to.point.bottomright.curvepath",
              url: AppConfig.baseURL.appendingPathComponent("planned_routes")),
    ]

    let navigators: [Navigator]
    var selection = 0
    var isRecording = RecordingController.shared.isActive
    var unsentCount = RecordingController.shared.unsentRecordingCount
    var reselectCount = 0

    init(delegate: NavigatorDelegate) {
        navigators = Self.specs.map {
            Navigator(configuration: .init(name: $0.name, startLocation: $0.url), delegate: delegate)
        }
        navigators.forEach { $0.start() }
        for name in [Notification.Name.recordingStateDidChange, .unsentRecordingsDidChange,
                     UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isRecording = RecordingController.shared.isActive
                self?.unsentCount = RecordingController.shared.unsentRecordingCount
            }
        }
    }

    var activeNavigator: Navigator { navigators[selection] }

    static func index(named name: String) -> Int? { specs.firstIndex { $0.name == name } }

    /// UITabBarController pops a reselected tab to its root for free; TabView
    /// only does that for a NavigationStack, so hosted navigators need it by hand.
    func select(_ index: Int) {
        if index == selection {
            reselectCount += 1
            navigators[index].rootViewController.popToRootViewController(animated: true)
        } else {
            selection = index
        }
    }
}

struct NavigatorView: UIViewControllerRepresentable {
    let navigator: Navigator
    func makeUIViewController(context: Context) -> UINavigationController { navigator.rootViewController }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

struct AppTabsView: View {
    let model: AppTabsModel
    let onFab: () -> Void

    var body: some View {
        TabView(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            ForEach(Array(AppTabsModel.specs.enumerated()), id: \.offset) { index, spec in
                NavigatorView(navigator: model.navigators[index])
                    .ignoresSafeArea()
                    .overlay(alignment: .bottomTrailing) { fab.padding(.trailing, 16).padding(.bottom, 12) }
                    .tabItem { Label(spec.title, systemImage: spec.systemImage) }
                    .tag(index)
            }
        }
        .tint(Color.accentColor)
        .modifier(MinimizeOnScroll())
    }

    private enum FabMode { case record, newActivity, newRoute }

    private var fabMode: FabMode {
        if model.isRecording { return .record }
        switch AppTabsModel.specs[model.selection].name {
        case "activities": return .newActivity
        case "planned_routes": return .newRoute
        default: return .record
        }
    }

    private var fab: some View {
        let mode = fabMode
        let label = switch mode {
        case .record: model.isRecording ? "Enregistrement en cours" : "Enregistrer"
        case .newActivity: "Nouvelle activité"
        case .newRoute: "Nouveau parcours"
        }
        return Button(action: onFab) {
            Image(systemName: mode == .record ? "record.circle" : "plus")
                .font(.system(size: 22))
                .frame(width: 56, height: 56)
                // Pulsing the whole glass button made it drop taps (they fell through
                // to the web view); pulsing only the glyph keeps it hit-testable.
                .modifier(Pulse(active: model.isRecording))
        }
        .modifier(FabStyle(color: model.isRecording ? .red : .accentColor))
        .accessibilityLabel(label)
        .overlay(alignment: .topTrailing) {
            if mode == .record, !model.isRecording, model.unsentCount > 0 {
                Text("\(model.unsentCount)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(.red))
                    .offset(x: 4, y: -4)
                    .accessibilityLabel(RecordingFormatters.unsentCount(model.unsentCount))
                    .accessibilityIdentifier("unsentBadge")
            }
        }
    }
}

private struct FabStyle: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(color)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(color)
        }
    }
}

/// The UIKit FAB needed a viewDidAppear dance to keep its CAAnimation removable;
/// SwiftUI owns the animation lifecycle.
private struct Pulse: ViewModifier {
    let active: Bool
    @State private var dimmed = false
    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.4 : 1)
            .animation(active ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: dimmed)
            .onAppear { dimmed = active }
            .onChange(of: active) { dimmed = active }
    }
}

private struct MinimizeOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

final class AppTabsController: UIHostingController<AppTabsView> {
    let model: AppTabsModel

    init(navigatorDelegate: NavigatorDelegate) {
        let model = AppTabsModel(delegate: navigatorDelegate)
        self.model = model
        weak var weakSelf: AppTabsController?
        super.init(rootView: AppTabsView(model: model) { weakSelf?.handleFab() })
        weakSelf = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func handleFab() {
        switch AppTabsModel.specs[model.selection].name {
        case _ where model.isRecording, "dashboard":
            let navigationController = UINavigationController(rootViewController: RecordingViewController())
            navigationController.modalPresentationStyle = .fullScreen
            navigationController.isModalInPresentation = true
            present(navigationController, animated: true)
        case "activities":
            RecordingController.shared.pendingHandoff = nil
            model.activeNavigator.route(AppConfig.baseURL.appendingPathComponent("activities/new"))
        default:
            model.activeNavigator.route(AppConfig.baseURL.appendingPathComponent("planned_routes/new"))
        }
    }

    func presentRecordingReview() {
        let navigator = model.activeNavigator
        navigator.route(AppConfig.baseURL.appendingPathComponent("activities/new"))
        navigator.modalRootViewController.isModalInPresentation = true
    }

    func route(_ url: URL, inTab name: String) {
        guard let index = AppTabsModel.index(named: name) else { return }
        model.selection = index
        model.activeNavigator.route(url)
    }
}
