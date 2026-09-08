import HotwireNative
import UIKit

/// The shell's half of the recording review (#116, ADR 0003 — supersedes #66).
/// The review screen is the web `/activities/new`; this hands it the finished
/// recording and acts on what the rider does with it.
final class RecordingReviewComponent: BridgeComponent {
    override class var name: String { "recording-review" }

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }

    override func onReceive(message: Message) {
        guard let event = Event(rawValue: message.event) else { return }
        switch event {
        case .connect: handleConnect()
        case .committed: handleCommitted(message: message)
        case .discard: handleDiscard()
        }
    }

    // MARK: - Events

    private func handleConnect() {
        reply(to: Event.connect.rawValue, with: HandoffData(handoff: encodedHandoff()))
    }

    /// `nil` when there is nothing to hand over. The page treats both the same
    /// way, so a failure to encode degrades to the plain upload form.
    private func encodedHandoff() -> String? {
        guard let handoff = RecordingController.shared.pendingHandoff else { return nil }
        do {
            return try handoff.encoded()
        } catch {
            NSLog("[RecordingReviewComponent] handoff encoding failed: \(error)")
            return nil
        }
    }

    /// Only now is it safe to drop the on-device recording (S0 §5).
    private func handleCommitted(message: Message) {
        let data: CommittedData? = message.data()
        clearPendingRecording()
        dismissReview { [weak self] in
            guard let url = data?.url.flatMap(URL.init(string:)) else { return }
            self?.routeToActivity(url)
        }
    }

    private func handleDiscard() {
        let alert = UIAlertController(
            title: "Supprimer cet enregistrement ?",
            message: "Cette action est définitive. L'enregistrement ne sera pas envoyé.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Supprimer", style: .destructive) { [weak self] _ in
            self?.clearPendingRecording()
            self?.dismissReview(completion: nil)
        })
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        viewController?.present(alert, animated: true)
    }

    // MARK: - Helpers

    private func clearPendingRecording() {
        let controller = RecordingController.shared
        guard let handoff = controller.pendingHandoff else { return }
        controller.discard(handoff.session)
    }

    private func dismissReview(completion: (() -> Void)?) {
        // Shared with the FAB's own modals, so hand it back dismissible.
        guard let modal = viewController?.navigationController else {
            completion?()
            return
        }
        modal.isModalInPresentation = false
        guard let presenter = modal.presentingViewController else {
            completion?()
            return
        }
        presenter.dismiss(animated: true) { completion?() }
    }

    private func routeToActivity(_ url: URL) {
        guard let window = viewController?.view.window ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
            let tabBar = window.rootViewController as? HotwireTabBarController,
            let index = HotwireTab.index(named: "activities") else { return }

        tabBar.selectedIndex = index
        tabBar.activeNavigator.route(url)
    }
}

// MARK: Events

private extension RecordingReviewComponent {
    enum Event: String {
        case connect
        case committed
        case discard
    }
}

// MARK: Message data

private extension RecordingReviewComponent {
    struct HandoffData: Encodable {
        let handoff: String?
    }

    struct CommittedData: Decodable {
        let url: String?
    }
}
