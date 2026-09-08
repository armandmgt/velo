import HotwireNative
import UIKit

/// The shell's half of the recording review (#116, ADR 0003 — supersedes #66).
///
/// The review screen is the web `/activities/new`; this hands it the finished
/// recording and listens for what the rider does with it:
/// - **connect** → reply with the compressed handoff, or `null` when there is no
///   pending recording (the tab bar's "+" routes to the same URL, where the page
///   must read as the plain upload form).
/// - **committed** → the page's upload succeeded; clear the local session and
///   land on the created activity in the Activités tab.
/// - **discard** → confirm, then drop the recording. Nothing was uploaded.
///
/// The shell no longer uploads anything itself: `ActivityUploader` and
/// `RecordingGPXEncoder` are gone, and the GPX is encoded on the web from the
/// points this component sends.
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

    /// The compressed handoff, or `nil` when there is nothing to hand over — the
    /// page treats both the same way, so a failure to encode degrades to the
    /// upload form rather than to a broken review screen.
    private func encodedHandoff() -> String? {
        guard let handoff = RecordingController.shared.pendingHandoff else { return nil }
        do {
            return try handoff.encoded()
        } catch {
            NSLog("[RecordingReviewComponent] handoff encoding failed: \(error)")
            return nil
        }
    }

    /// The upload landed. Only now is it safe to drop the on-device recording —
    /// the store is the source of truth until the server has confirmed (S0 §5,
    /// weakened by ADR 0003 and bought back by the `recording_uuid` the page
    /// submitted, which makes a replay resolve to this same activity).
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
        // The modal navigator is shared with the FAB's own `/activities/new` and
        // `/planned_routes/new`, so hand it back ordinarily dismissible.
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

    /// Land on the created activity in the tab that owns activities, mirroring
    /// the cross-tab routing the path configuration declares.
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
        /// Raw DEFLATE, base64'd. `nil` when there is no pending recording.
        let handoff: String?
    }

    struct CommittedData: Decodable {
        /// Where the form submission landed — the created activity.
        let url: String?
    }
}
