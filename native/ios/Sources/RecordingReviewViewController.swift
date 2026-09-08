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
///
/// Laid out map-hero (S12a — #60): the route fills the top of the screen, a flat
/// card rides up over its lower edge carrying the distance and the two clocks,
/// and the laps collapse to one row that opens the split sheet. Same flat
/// vocabulary as the recording screen — see `FlatStyle`.
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

    private let heroValueLabel = FlatStyle.number(size: 52, weight: .heavy, color: Palette.accent)
    private let heroUnitLabel = UILabel()

    // Two clocks, both shown: the number a rider reads here must never be mistaken
    // for the stricter one the activity page shows after upload. The caption is
    // shortened to fit a third of the card — "Durée de déplacement" is the term
    // (CONTEXT.md), "Déplacement" is the label.
    private let elapsedValue = FlatStyle.number(size: 21, weight: .bold)
    private let movingValue = FlatStyle.number(size: 21, weight: .bold)
    private let avgValue = FlatStyle.number(size: 21, weight: .bold)
    private let avgCaption = FlatStyle.caption("Moy. km/h")

    /// A still rendering of the trace just recorded — the hero of this screen.
    private let mapPreview = RecordingMapView(preview: true)

    private let scrollView = UIScrollView()

    // The laps collapse to a single row; the full table lives in the sheet.
    private let lapCountBadge = FlatStyle.number(size: 14, weight: .heavy, color: .white)
    private let lapSummaryTitle = UILabel()
    private let lapSummaryDetail = FlatStyle.number(size: 13, weight: .regular, color: Palette.muted)
    private lazy var lapSummaryRow = makeLapSummaryRow()

    private lazy var sportButton = makeSportButton()

    private let nameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Sortie du matin…"
        field.borderStyle = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = Palette.ink
        field.textAlignment = .right
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.accessibilityIdentifier = "activityName"
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var visibilitySegmented: FlatSegmentedControl = {
        let control = FlatSegmentedControl(
            titles: Visibility.allCases.map(\.displayName),
            selectedIndex: Visibility.allCases.firstIndex(of: visibility) ?? 0
        )
        control.onChange = { [weak self] index in self?.visibilityChanged(index) }
        return control
    }()

    // The same two shapes the recording screen ends on: a green fill for the
    // committing action, a red-outlined white card for the destructive one.
    private lazy var saveButton: UIButton = {
        let button = makeFlatButton(title: "Enregistrer", size: 17, weight: .bold)
        button.backgroundColor = Palette.green
        button.setTitleColor(Palette.greenText, for: .normal)
        button.addAction(UIAction { [weak self] _ in self?.save() }, for: .primaryActionTriggered)
        return button
    }()

    private lazy var deleteButton: UIButton = {
        let button = makeFlatButton(title: "Supprimer", size: 16, weight: .semibold)
        button.backgroundColor = .white
        button.setTitleColor(Palette.red, for: .normal)
        button.layer.borderWidth = 1
        button.layer.borderColor = Palette.redBorder.cgColor
        button.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .primaryActionTriggered)
        return button
    }()

    private func makeFlatButton(title: String, size: CGFloat, weight: UIFont.Weight) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: size, weight: weight)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// Everything that rides below the map: the hero card (pulled up over the
    /// map's lower edge), the collapsed lap row, then the form.
    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [summaryCard, lapSummaryRow, formCard])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var summaryCard = makeSummaryCard()
    private lazy var formCard = makeFormCard()

    /// The floating title, in the same flat pill the recording screen uses for its
    /// state — the nav bar is hidden here so the map can run to the top edge.
    private lazy var titlePill: UIView = {
        let pill = FlatStyle.card(shadowOpacity: 0.12, shadowRadius: 3, shadowY: 1)
        let label = UILabel()
        label.text = "Vérifier la sortie".uppercased()
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = Palette.ink
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
        ])
        return pill
    }()

    private lazy var actionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [deleteButton, saveButton])
        stack.axis = .horizontal
        stack.spacing = 8
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

        view.backgroundColor = Palette.page
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The route runs to the top edge, so the bar would only sit on top of it.
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: - Layout

    private func setupLayout() {
        heroValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        heroUnitLabel.setContentHuggingPriority(.required, for: .horizontal)

        // The map is the hero: full-bleed to the top edge, with the content card
        // riding up over its lower edge the way the dock does while recording.
        mapPreview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapPreview)
        view.addSubview(titlePill)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        view.addSubview(actionStack)
        view.addSubview(uploadingStack)

        NSLayoutConstraint.activate([
            mapPreview.topAnchor.constraint(equalTo: view.topAnchor),
            mapPreview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapPreview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapPreview.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),

            titlePill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            titlePill.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // -46 is the overlap: the card sits on the map, not under it.
            scrollView.topAnchor.constraint(equalTo: mapPreview.bottomAnchor, constant: -46),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -10),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -12),

            actionStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            actionStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            saveButton.heightAnchor.constraint(equalToConstant: 52),
            deleteButton.heightAnchor.constraint(equalTo: saveButton.heightAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 118),

            uploadingStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadingStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Let the scroll view hug its content so the map absorbs the slack rather
        // than leaving a dead band above the actions. Breaks (and the content
        // scrolls) when the summary is taller than the space left.
        let hug = scrollView.heightAnchor.constraint(equalTo: contentStack.heightAnchor, constant: 12)
        hug.priority = .defaultHigh
        hug.isActive = true
    }

    /// The hero card: the distance and the sport on one line, then the three
    /// numbers under a hairline. Flat white with the dock's border + shadow, so it
    /// reads as the same object that floats over the map while recording.
    private func makeSummaryCard() -> UIView {
        let card = FlatStyle.card(border: Palette.borderDock, shadowOpacity: 0.12, shadowRadius: 18, shadowY: 8)

        heroUnitLabel.text = "km"
        heroUnitLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        heroUnitLabel.textColor = Palette.muted

        let heroRow = UIStackView(arrangedSubviews: [heroValueLabel, heroUnitLabel, UIView(), sportButton])
        heroRow.axis = .horizontal
        heroRow.alignment = .lastBaseline
        heroRow.spacing = 6
        heroRow.isLayoutMarginsRelativeArrangement = true
        heroRow.directionalLayoutMargins = .init(top: 14, leading: 16, bottom: 12, trailing: 14)

        let statsRow = UIStackView(arrangedSubviews: [
            statCell(value: elapsedValue, caption: FlatStyle.caption("Temps écoulé")),
            FlatStyle.hairline(vertical: true),
            statCell(value: movingValue, caption: FlatStyle.caption("Déplacement")),
            FlatStyle.hairline(vertical: true),
            statCell(value: avgValue, caption: avgCaption),
        ])
        statsRow.axis = .horizontal
        statsRow.alignment = .fill
        statsRow.distribution = .fill

        let stack = UIStackView(arrangedSubviews: [heroRow, FlatStyle.hairline(), statsRow])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    /// One of the three centred number-over-caption cells.
    private func statCell(value: UILabel, caption: UILabel) -> UIView {
        value.textAlignment = .center
        caption.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [value, caption])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 11, leading: 4, bottom: 11, trailing: 4)
        return stack
    }

    /// The laps, collapsed: an accent-filled count, the lap total, and the split
    /// distances. Tapping it opens the same sheet the recording dock opens.
    private func makeLapSummaryRow() -> UIView {
        let card = FlatStyle.card()
        card.accessibilityIdentifier = "lapSummaryRow"

        lapCountBadge.textAlignment = .center
        let badge = UIView()
        badge.backgroundColor = Palette.accent
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(lapCountBadge)
        lapCountBadge.translatesAutoresizingMaskIntoConstraints = false

        lapSummaryTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        lapSummaryTitle.textColor = Palette.ink

        let text = UIStackView(arrangedSubviews: [lapSummaryTitle, lapSummaryDetail])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 1

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Palette.muted
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [badge, text, UIView(), chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 13, leading: 14, bottom: 13, trailing: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        card.isUserInteractionEnabled = true
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showLapSplits)))

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            badge.widthAnchor.constraint(equalToConstant: 30),
            badge.heightAnchor.constraint(equalToConstant: 30),
            lapCountBadge.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            lapCountBadge.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 13),
        ])
        return card
    }

    /// Nom + Visibilité as two hairline-separated rows in one flat card.
    private func makeFormCard() -> UIView {
        let card = FlatStyle.card()

        let nameRow = formRow(caption: "Nom", control: nameField)
        let visibilityRow = formRow(caption: "Visibilité", control: visibilitySegmented)

        let stack = UIStackView(arrangedSubviews: [nameRow, FlatStyle.hairline(), visibilityRow])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    private func formRow(caption: String, control: UIView) -> UIView {
        let row = UIStackView(arrangedSubviews: [FlatStyle.caption(caption), control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 10, leading: 14, bottom: 10, trailing: 14)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    /// The sport picker, inline on the hero row: icon + name + a chevron, no
    /// surface of its own — the card it sits on is the surface.
    private func makeSportButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.imagePadding = 6
        config.contentInsets = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
        config.baseForegroundColor = Palette.ink
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 14, weight: .semibold)
            return attributes
        }
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "sportPicker"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func updateSportButton() {
        sportButton.configuration?.title = sport.displayName
        sportButton.configuration?.image = UIImage(systemName: sport.symbolName)
        sportButton.menu = makeSportMenu()
        avgCaption.text = (sport.usesPace ? "Allure" : "Moy. km/h").uppercased()
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
        elapsedValue.text = RecordingFormatters.elapsedString(stats.elapsed)
        movingValue.text = RecordingFormatters.elapsedString(stats.movingTime)
        // The unit already lives in the caption, so the cell shows the bare number.
        avgValue.text = sport.usesPace
            ? RecordingFormatters.pace(stats.averageSpeed)
            : String(format: "%.1f", max(stats.averageSpeed, 0) * 3.6)

        let splits = lapSplits
        lapCountBadge.text = "\(splits.count)"
        lapSummaryTitle.text = splits.count == 1 ? "1 tour" : "\(splits.count) tours"
        lapSummaryDetail.text = splits
            .map { RecordingFormatters.distanceKilometers($0.distance) }
            .joined(separator: " · ") + " km"
    }

    /// The finished recording's splits — shown collapsed here, in full in the sheet.
    private var lapSplits: [LapSplit] {
        LapSplits.splits(
            boundaries: session.lapBoundaries,
            totalDistance: stats.distance,
            totalElapsed: stats.elapsed,
            isFinished: true
        )
    }

    /// Open the full split table, the same sheet the recording dock opens.
    @objc private func showLapSplits() {
        present(
            LapSplitsViewController(
                splits: lapSplits,
                usesPace: sport.usesPace,
                summary: "\(RecordingFormatters.distanceKilometers(stats.distance)) km · \(RecordingFormatters.elapsedString(stats.elapsed))"
            ),
            animated: true
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

    private func visibilityChanged(_ index: Int) {
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
