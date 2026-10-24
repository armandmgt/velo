import HotwireNative
import UIKit

/// Hands the finished recording to the review screen, which is the web
/// `/activities/new`, and acts on what the rider does with it.
final class RecordingReviewComponent: BridgeComponent {
    override class var name: String { "recording-review" }

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }

    /// The recording this page was opened for, taken when it first connects.
    /// Committing or discarding clears this one, never whatever is pending by
    /// then, so a resent review and a fresh one can't clear each other's.
    private var handoff: RecordingHandoff?

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

    /// `nil` leaves the page reading as the plain upload form, which is also the
    /// right answer if encoding fails.
    private func encodedHandoff() -> String? {
        handoff = handoff ?? RecordingController.shared.pendingHandoff
        guard let handoff else { return nil }
        do {
            return try handoff.encoded()
        } catch {
            NSLog("[RecordingReviewComponent] handoff encoding failed: \(error)")
            return nil
        }
    }

    private func handleCommitted(message: Message) {
        let data: CommittedData? = message.data()
        clearRecording()
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
            self?.clearRecording()
            self?.dismissReview(completion: nil)
        })
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        viewController?.present(alert, animated: true)
    }

    // MARK: - Helpers

    private func clearRecording() {
        guard let handoff else { return }
        RecordingController.shared.discard(handoff.session)
        self.handoff = nil
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
