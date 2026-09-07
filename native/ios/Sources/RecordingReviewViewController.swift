import CoreLocation
import HotwireNative
import UIKit

/// The native review/confirm screen shown after **Arrêter**, before upload
/// (#41, S13 — #66).
///
/// Stop finalizes the recording (it stays in Core Data) and pushes this screen
/// instead of uploading immediately, so the user can review the summary, adjust
/// the sport/visibility, optionally name it, then either:
/// - **Enregistrer**: serialize to GPX + `POST /activities` (the S4 happy path)
///   → on success clear the local session and jump to the new activity; on
///   failure keep the recording and offer a retry.
/// - **Supprimer**: after a confirmation, discard the local session — no activity
///   is created server-side.
///
/// It owns the upload flow that used to live on `RecordingViewController`. The
/// stats are a snapshot captured at Stop (the controller's elapsed clock is reset
/// by `stop()`), so this screen reads them rather than the live controller.
final class RecordingReviewViewController: UIViewController {
    private var controller: RecordingController { .shared }

    private let session: RecordingSession
    private let stats: RecordingStats
    private var sport: Sport
    private var visibility: Visibility = .default

    init(session: RecordingSession, stats: RecordingStats) {
        self.session = session
        self.stats = stats
        self.sport = RecordingController.shared.sport
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Subviews

    private let heroValueLabel = UILabel()
    private let heroUnitLabel = UILabel()
    private let heroCaptionLabel = UILabel()

    // Two clocks, named exactly as CONTEXT.md defines them: the review screen
    // shows both, so the number here is never mistaken for the (stricter) one the
    // activity page will show after upload.
    private let elapsedStat = StatView(caption: "Temps écoulé")
    private let movingStat = StatView(caption: "Durée de déplacement")
    private let avgStat = StatView(caption: "Moyenne")

    /// A still rendering of the trace just recorded.
    private let mapPreview = RecordingMapView(preview: true)

    private let scrollView = UIScrollView()

    private lazy var lapSplitsView = LapSplitsView(usesPace: sport.usesPace)

    private lazy var sportButton = makeSportButton()

    private let nameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Nom (facultatif)"
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.accessibilityIdentifier = "activityName"
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var visibilitySegmented: UISegmentedControl = {
        let control = UISegmentedControl(items: Visibility.allCases.map(\.displayName))
        control.selectedSegmentIndex = Visibility.allCases.firstIndex(of: visibility) ?? 0
        control.addAction(UIAction { [weak self] _ in self?.visibilityChanged() }, for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var saveButton: UIButton = {
        let button = GlassButton.make(prominent: true, tint: .systemGreen)
        button.configuration?.title = "Enregistrer"
        button.addAction(UIAction { [weak self] _ in self?.save() }, for: .primaryActionTriggered)
        return button
    }()

    private lazy var deleteButton: UIButton = {
        let button = GlassButton.make(prominent: true, tint: .systemRed)
        button.configuration?.title = "Supprimer"
        button.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .primaryActionTriggered)
        return button
    }()

    private lazy var contentStack: UIStackView = {
        let heroRow = UIStackView(arrangedSubviews: [heroValueLabel, heroUnitLabel])
        heroRow.axis = .horizontal
        heroRow.alignment = .lastBaseline
        heroRow.spacing = 6
        let heroBlock = UIStackView(arrangedSubviews: [heroRow, heroCaptionLabel])
        heroBlock.axis = .vertical
        heroBlock.alignment = .center
        heroBlock.spacing = 2

        let stack = UIStackView(arrangedSubviews: [
            heroBlock,
            mapCard,
            summaryCard,
            makeField(caption: "Tours", control: lapSplitsView, fillWidth: true),
            makeField(caption: "Sport", control: sportButton, fillWidth: false),
            makeField(caption: "Nom", control: nameField, fillWidth: true),
            makeField(caption: "Visibilité", control: visibilitySegmented, fillWidth: true),
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.setCustomSpacing(24, after: heroBlock)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var summaryCard = makeSummaryCard()

    /// The route preview, clipped to the same rounded card as the summary.
    private lazy var mapCard: UIView = {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(mapPreview)
        NSLayoutConstraint.activate([
            mapPreview.topAnchor.constraint(equalTo: card.topAnchor),
            mapPreview.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            mapPreview.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            mapPreview.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            // Tall enough that the MapTiler attribution stays legible.
            card.heightAnchor.constraint(equalToConstant: 200),
        ])
        return card
    }()

    private lazy var actionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [saveButton, deleteButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let uploadingSpinner = UIActivityIndicatorView(style: .medium)
    private lazy var uploadingStack: UIStackView = {
        let label = UILabel()
        label.text = "Envoi en cours…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [uploadingSpinner, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Vérifier la sortie"
        // Terminal after Stop — the only ways out are Enregistrer / Supprimer.
        navigationItem.hidesBackButton = true

        setupLayout()
        updateSportButton()
        render()
        mapPreview.showRoutePreview(
            session.orderedPoints.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        )

        // The name field now sits below the map and the split list, so the keyboard
        // would cover it without an inset.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        // Dismiss the keyboard when tapping outside the name field.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        nameField.delegate = self
    }

    // MARK: - Layout

    private func setupLayout() {
        heroValueLabel.font = .monospacedDigitSystemFont(ofSize: 64, weight: .semibold)
        heroValueLabel.textColor = .label
        heroValueLabel.adjustsFontSizeToFitWidth = true
        heroValueLabel.minimumScaleFactor = 0.6

        heroUnitLabel.text = "km"
        heroUnitLabel.font = .systemFont(ofSize: 22, weight: .medium)
        heroUnitLabel.textColor = .secondaryLabel

        heroCaptionLabel.text = "DISTANCE"
        heroCaptionLabel.font = .preferredFont(forTextStyle: .caption1)
        heroCaptionLabel.textColor = .secondaryLabel

        // The map and the split list push the summary past a phone screen, so the
        // review content scrolls while the actions stay pinned to the bottom.
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.addSubview(contentStack)

        view.addSubview(scrollView)
        view.addSubview(actionStack)
        view.addSubview(uploadingStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),

            actionStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            actionStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            actionStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            saveButton.heightAnchor.constraint(equalToConstant: 54),
            deleteButton.heightAnchor.constraint(equalToConstant: 54),

            uploadingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadingStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// A captioned form field: an upper-cased caption above a control. When
    /// `fillWidth` is false the control hugs its content, left-aligned (the sport
    /// chip); otherwise it stretches (name field, visibility picker).
    private func makeField(caption: String, control: UIView, fillWidth: Bool) -> UIStackView {
        let captionLabel = UILabel()
        captionLabel.text = caption.uppercased()
        captionLabel.font = .preferredFont(forTextStyle: .caption2)
        captionLabel.textColor = .secondaryLabel

        let row: UIView
        if fillWidth {
            row = control
        } else {
            // Wrap so the chip stays left-aligned instead of stretching full width.
            let wrapper = UIStackView(arrangedSubviews: [control, UIView()])
            wrapper.axis = .horizontal
            row = wrapper
        }

        let stack = UIStackView(arrangedSubviews: [captionLabel, row])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        return stack
    }

    /// A filled, rounded card with the two read-only summary stats (Temps ·
    /// Moyenne) split by a vertical hairline — same treatment as the dashboard's
    /// metric card.
    private func makeSummaryCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let separator2 = UIView()
        separator2.backgroundColor = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [elapsedStat, separator, movingStat, separator2, avgStat])
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = 0
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 22, leading: 0, bottom: 22, trailing: 0)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 0.5),
            separator2.widthAnchor.constraint(equalToConstant: 0.5),
            elapsedStat.widthAnchor.constraint(equalTo: avgStat.widthAnchor),
            movingStat.widthAnchor.constraint(equalTo: avgStat.widthAnchor),
        ])
        return card
    }

    private func makeSportButton() -> UIButton {
        let button = GlassButton.make(prominent: false)
        button.configuration?.imagePadding = 6
        button.configuration?.contentInsets = .init(top: 8, leading: 14, bottom: 8, trailing: 14)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "sportPicker"
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func updateSportButton() {
        sportButton.configuration?.title = sport.displayName
        sportButton.configuration?.image = UIImage(systemName: sport.symbolName)
        sportButton.menu = makeSportMenu()
        avgStat.caption = sport.usesPace ? "Allure" : "Moyenne"
        render()
    }

    private func makeSportMenu() -> UIMenu {
        let actions = Sport.allCases.map { option in
            UIAction(
                title: option.displayName,
                image: UIImage(systemName: option.symbolName),
                state: option == sport ? .on : .off
            ) { [weak self] _ in
                self?.sport = option
                self?.updateSportButton()
            }
        }
        return UIMenu(title: "Sport", children: actions)
    }

    // MARK: - Rendering

    private func render() {
        heroValueLabel.text = RecordingFormatters.distanceKilometers(stats.distance)
        elapsedStat.value = RecordingFormatters.elapsedString(stats.elapsed)
        movingStat.value = RecordingFormatters.elapsedString(stats.movingTime)
        avgStat.value = RecordingFormatters.speedOrPace(stats.averageSpeed, usesPace: sport.usesPace)
        lapSplitsView.usesPace = sport.usesPace
        lapSplitsView.setSplits(
            LapSplits.splits(
                boundaries: session.lapBoundaries,
                totalDistance: stats.distance,
                totalElapsed: stats.elapsed,
                isFinished: true
            )
        )
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overlap = max(view.bounds.maxY - view.convert(frame, from: nil).minY - actionStack.frame.height, 0)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        if nameField.isFirstResponder {
            scrollView.scrollRectToVisible(nameField.convert(nameField.bounds, to: scrollView), animated: true)
        }
    }

    @objc private func keyboardWillHide() {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    private func visibilityChanged() {
        let index = visibilitySegmented.selectedSegmentIndex
        guard Visibility.allCases.indices.contains(index) else { return }
        visibility = Visibility.allCases[index]
    }

    // MARK: - Actions

    /// Serialize the finalized session to GPX and POST it. On success the local
    /// session is cleared and the webview jumps to the new activity; on failure
    /// the recording is kept (still in Core Data) and a retry is offered.
    private func save() {
        dismissKeyboard()
        enterUploadingState()
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let gpx = RecordingGPXEncoder.gpx(for: session, sport: sport)
        ActivityUploader.upload(gpx: gpx, sport: sport, name: name, visibility: visibility) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.controller.discard(self.session)
                self.navigateToActivity(url)
            case .failure(let error):
                self.exitUploadingState()
                self.presentUploadFailure(error)
            }
        }
    }

    /// Discard the recording after confirmation — nothing is uploaded.
    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Supprimer cet enregistrement ?",
            message: "Cette action est définitive. L'enregistrement ne sera pas envoyé.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Supprimer", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.controller.discard(self.session)
            self.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        present(alert, animated: true)
    }

    /// Push the created activity onto the Activités tab, then dismiss the modal to
    /// reveal it. Mirrors `RecordingViewController`'s former tab-bar reach.
    private func navigateToActivity(_ url: URL) {
        if let tabBar = view.window?.rootViewController as? HotwireTabBarController {
            tabBar.selectedIndex = 1 // Activités
            tabBar.activeNavigator.route(url)
        }
        dismiss(animated: true)
    }

    private func presentUploadFailure(_ error: ActivityUploader.UploadError) {
        let message: String
        switch error {
        case .validation(let errors):
            message = errors.joined(separator: "\n")
        case .network:
            message = "L'enregistrement a été conservé. Vérifiez votre connexion, puis réessayez."
        }
        let alert = UIAlertController(title: "Envoi échoué", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Réessayer", style: .default) { [weak self] _ in
            self?.save()
        })
        alert.addAction(UIAlertAction(title: "Plus tard", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func enterUploadingState() {
        contentStack.isHidden = true
        actionStack.isHidden = true
        uploadingStack.isHidden = false
        uploadingSpinner.startAnimating()
    }

    private func exitUploadingState() {
        uploadingSpinner.stopAnimating()
        uploadingStack.isHidden = true
        contentStack.isHidden = false
        actionStack.isHidden = false
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}

// MARK: - UITextFieldDelegate

extension RecordingReviewViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
