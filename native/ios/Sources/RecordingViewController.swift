import CoreLocation
import HotwireNative
import UIKit

/// The design's flat, light palette (Recording.dc.html): sharp-cornered white
/// surfaces with thin borders — deliberately *not* native (no Liquid Glass /
/// system materials), so the native screen matches the web pixel-for-pixel.
private enum Palette {
    static func hex(_ v: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
    static let ink = hex(0x161616)        // primary text        — oklch(20% 0 0)
    static let muted = hex(0x555555)      // captions / secondary — oklch(45% 0 0)
    static let border = hex(0xCECECE)     // chip / button border — oklch(85% 0 0)
    static let borderDock = hex(0xD7D7D7) // dock border          — oklch(88% 0 0)
    static let divider = hex(0xE4E4E4)    // internal dividers    — oklch(92% 0 0)
    static let grabber = hex(0xC4C4C4)    // grab handle          — oklch(82% 0 0)
    static let green = hex(0x20C45F)      // Démarrer fill        — oklch(72% 0.19 150)
    static let greenText = hex(0x08351A)  // Démarrer text        — oklch(24% 0.06 153)
    static let redBorder = hex(0xFF627E)  // Arrêter border       — oklch(71% 0.194 13.4)
    static let red = hex(0xDD1B53)        // Arrêter / rec pill   — oklch(58% 0.22 13.4)
    static let paused = hex(0xD36000)     // paused pill          — oklch(62% 0.18 56)
}

/// The native recording surface (#41), redesigned map-centric + flat per
/// `Recording.dc.html`.
///
/// A full-bleed live `RecordingMapView` sits behind everything; over it float the
/// header chips (sport ⟷ GPS), a state pill, and a collapsible bottom dock. Every
/// overlay surface is a flat white sharp-cornered card with a thin border (no
/// system materials). The dock's expanded layout is Distance | Temps over a
/// Vitesse · Moyenne · Tours row.
///
/// Flow (explicit start): opening *arms* the GPS ("GPS prêt") without recording.
/// **Démarrer** starts; **Pause/Reprendre** and **Tour** drive what's recorded.
/// **Fermer** leaves while recording continues in the background; **Arrêter**
/// finalizes and pushes the native review/confirm screen.
final class RecordingViewController: UIViewController {
    private var controller: RecordingController { .shared }

    /// Orange accent (route trace + distance/speed values), from the server-delivered
    /// map config (matches the web `--color-primary` / the mockup's route colour).
    private let accentColor = MapConfig.current.accentColor

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = ""

        // Transparent nav bar so the map bleeds to the top edge; only Fermer floats.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Fermer",
            primaryAction: UIAction { [weak self] _ in self?.close() }
        )

        setupLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        controller.delegate = self
        updateSportButton()
        render(state: controller.state)
        render(stats: controller.currentStats)
        seedMap()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        controller.arm()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        controller.disarmIfIdle()
    }

    // MARK: - Views

    private let mapView = RecordingMapView()
    private let gpsChip = GPSChipView()
    private let statePill = StatusPillView()

    // Compact dock labels (one-row summary).
    private let compactDistanceLabel = UILabel()
    private let compactUnitLabel = UILabel()
    private let compactElapsedLabel = UILabel()
    private let compactSpeedLabel = UILabel()

    // Expanded dock — top row (Distance | Temps).
    private let distanceValue = UILabel()
    private let distanceUnit = UILabel()
    private let timeBig = UILabel()
    private let timeSmall = UILabel()

    // Expanded dock — bottom 3-cell row (Vitesse · Moyenne · Tours).
    private let vitValue = UILabel()
    private let vitCaption = UILabel()
    private let moyValue = UILabel()
    private let moyCaption = UILabel()
    private let toursValue = UILabel()

    private lazy var sportButton = makeSportButton()
    private lazy var startButton = makeStartButton()
    private lazy var lapButton = makeOutlineButton(title: "Tour") { [weak self] in self?.markLap() }
    private lazy var pauseResumeButton = makeOutlineButton(title: "Pause") { [weak self] in self?.togglePause() }
    private lazy var stopButton = makeStopButton()

    private var dockCollapsed = false

    private lazy var grabberButton = makeGrabber()
    private lazy var idleCard = makeIdleCard()
    private lazy var compactStats = makeCompactStats()
    private lazy var expandedStats = makeExpandedStats()
    private lazy var dockView = makeDock()

    /// Header: sport chip ⟷ GPS chip.
    private lazy var headerStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [sportButton, gpsChip])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// A flat white sharp-cornered capsule backing the state pill so it reads over
    /// the map (matching the design's bordered pill).
    private lazy var pillContainer: UIView = {
        let container = flatCard(border: Palette.border, shadowOpacity: 0.12, shadowRadius: 3, shadowY: 1)
        container.addSubview(statePill)
        NSLayoutConstraint.activate([
            statePill.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            statePill.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            statePill.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            statePill.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])
        return container
    }()

    /// Controls row: idle → Démarrer; recording → Tour · Pause · Arrêter; paused →
    /// Reprendre · Arrêter (Tour hidden).
    private lazy var activeControls: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [lapButton, pauseResumeButton, stopButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var bottomOverlay: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [dockView, startButton, activeControls])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private func setupLayout() {
        gpsChip.onTapWhenDenied = {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }

        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        view.addSubview(headerStack)
        view.addSubview(pillContainer)
        view.addSubview(bottomOverlay)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),

            pillContainer.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            pillContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            bottomOverlay.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bottomOverlay.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            bottomOverlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            startButton.heightAnchor.constraint(equalToConstant: 52),
            lapButton.heightAnchor.constraint(equalToConstant: 50),
            pauseResumeButton.heightAnchor.constraint(equalToConstant: 50),
            stopButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    // MARK: - Flat surface helpers

    /// A flat white card with a 1px border, sharp corners, and a soft shadow — the
    /// design's base surface for chips / pill / dock.
    private func flatCard(border: UIColor, shadowOpacity: Float, shadowRadius: CGFloat, shadowY: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.borderWidth = 1
        view.layer.borderColor = border.cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = shadowOpacity
        view.layer.shadowRadius = shadowRadius
        view.layer.shadowOffset = CGSize(width: 0, height: shadowY)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func hairline(vertical: Bool) -> UIView {
        let view = UIView()
        view.backgroundColor = Palette.divider
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: vertical ? .horizontal : .vertical)
        return view
    }

    /// A small caption row: a tinted SF icon + an uppercase muted label (Distance /
    /// Temps headers in the expanded dock).
    private func captionRow(symbol: String, text: String) -> UIStackView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Palette.muted
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 13).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 13).isActive = true

        let label = UILabel()
        label.text = text.uppercased()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Palette.muted

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5
        return stack
    }

    // MARK: - Dock construction

    private func makeDock() -> UIView {
        let card = flatCard(border: Palette.borderDock, shadowOpacity: 0.22, shadowRadius: 18, shadowY: 8)

        let content = UIStackView(arrangedSubviews: [grabberButton, idleCard, compactStats, expandedStats])
        content.axis = .vertical
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    private func grabHandle() -> UIView {
        let bar = UIView()
        bar.backgroundColor = Palette.grabber
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: 36),
            bar.heightAnchor.constraint(equalToConstant: 5),
        ])
        return bar
    }

    private func makeGrabber() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let bar = grabHandle()
        bar.isUserInteractionEnabled = false
        button.addSubview(bar)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 24),
            bar.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            bar.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.addAction(UIAction { [weak self] _ in self?.toggleDock() }, for: .primaryActionTriggered)
        button.accessibilityLabel = "Réduire ou agrandir les statistiques"
        button.accessibilityIdentifier = "dockGrabber"
        return button
    }

    private func makeIdleCard() -> UIView {
        let handle = grabHandle()

        let title = UILabel()
        title.text = "PRÊT À ENREGISTRER"
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = Palette.muted
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Le GPS est calé sur votre position."
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = Palette.muted
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [handle, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.setCustomSpacing(16, after: handle)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 16, leading: 20, bottom: 22, trailing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeCompactStats() -> UIView {
        compactDistanceLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .heavy)
        compactDistanceLabel.textColor = accentColor
        compactDistanceLabel.text = "0.00"

        compactUnitLabel.text = "km"
        compactUnitLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        compactUnitLabel.textColor = Palette.muted

        let distanceRow = UIStackView(arrangedSubviews: [compactDistanceLabel, compactUnitLabel])
        distanceRow.axis = .horizontal
        distanceRow.alignment = .lastBaseline
        distanceRow.spacing = 4

        let divider = hairline(vertical: true)

        compactElapsedLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        compactElapsedLabel.textColor = Palette.ink
        compactElapsedLabel.text = "0:00"

        compactSpeedLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        compactSpeedLabel.textColor = accentColor
        compactSpeedLabel.text = "0.0 km/h"
        compactSpeedLabel.setContentHuggingPriority(.required, for: .horizontal)
        compactSpeedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [distanceRow, divider, compactElapsedLabel, spacer, compactSpeedLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 16
        stack.distribution = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 2, leading: 20, bottom: 16, trailing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 26),
        ])
        return stack
    }

    private func makeExpandedStats() -> UIView {
        // --- Top row: Distance | Temps, two equal columns split by a hairline. ---
        distanceValue.font = .monospacedDigitSystemFont(ofSize: 40, weight: .heavy)
        distanceValue.textColor = accentColor
        distanceValue.text = "0.00"
        distanceValue.adjustsFontSizeToFitWidth = true
        distanceValue.minimumScaleFactor = 0.6

        distanceUnit.text = "km"
        distanceUnit.font = .systemFont(ofSize: 15, weight: .semibold)
        distanceUnit.textColor = Palette.muted
        distanceUnit.setContentCompressionResistancePriority(.required, for: .horizontal)

        let distanceValueRow = UIStackView(arrangedSubviews: [distanceValue, distanceUnit])
        distanceValueRow.axis = .horizontal
        distanceValueRow.alignment = .lastBaseline
        distanceValueRow.spacing = 5

        let distanceCol = UIStackView(arrangedSubviews: [captionRow(symbol: "waveform.path.ecg", text: "Distance"), distanceValueRow])
        distanceCol.axis = .vertical
        distanceCol.alignment = .leading
        distanceCol.spacing = 2
        distanceCol.isLayoutMarginsRelativeArrangement = true
        distanceCol.directionalLayoutMargins = .init(top: 2, leading: 20, bottom: 14, trailing: 16)

        timeBig.font = .monospacedDigitSystemFont(ofSize: 40, weight: .heavy)
        timeBig.textColor = Palette.ink
        timeBig.text = "0"
        timeBig.adjustsFontSizeToFitWidth = true
        timeBig.minimumScaleFactor = 0.6

        timeSmall.font = .monospacedDigitSystemFont(ofSize: 19, weight: .bold)
        timeSmall.textColor = Palette.muted
        timeSmall.text = ":00"
        timeSmall.setContentCompressionResistancePriority(.required, for: .horizontal)

        let timeValueRow = UIStackView(arrangedSubviews: [timeBig, timeSmall])
        timeValueRow.axis = .horizontal
        timeValueRow.alignment = .lastBaseline
        timeValueRow.spacing = 0

        let timeCol = UIStackView(arrangedSubviews: [captionRow(symbol: "clock", text: "Temps"), timeValueRow])
        timeCol.axis = .vertical
        timeCol.alignment = .leading
        timeCol.spacing = 2
        timeCol.isLayoutMarginsRelativeArrangement = true
        timeCol.directionalLayoutMargins = .init(top: 2, leading: 16, bottom: 14, trailing: 20)

        let vDivider = hairline(vertical: true)
        let topRow = UIStackView(arrangedSubviews: [distanceCol, vDivider, timeCol])
        topRow.axis = .horizontal
        topRow.alignment = .fill
        topRow.distribution = .fill

        // --- Bottom row: Vitesse · Moyenne · Tours, three equal cells. ---
        let vitCell = statCell(value: vitValue, valueColor: accentColor, caption: vitCaption, captionText: "Vit. km/h")
        let moyCell = statCell(value: moyValue, valueColor: Palette.ink, caption: moyCaption, captionText: "Moy. km/h")
        let toursCap = UILabel()
        let toursCell = statCell(value: toursValue, valueColor: Palette.ink, caption: toursCap, captionText: "Tours")

        let d1 = hairline(vertical: true)
        let d2 = hairline(vertical: true)
        let bottomRow = UIStackView(arrangedSubviews: [vitCell, d1, moyCell, d2, toursCell])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .fill
        bottomRow.distribution = .fill

        let hDivider = hairline(vertical: false)

        let stack = UIStackView(arrangedSubviews: [topRow, hDivider, bottomRow])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            distanceCol.widthAnchor.constraint(equalTo: timeCol.widthAnchor),
            vDivider.widthAnchor.constraint(equalToConstant: 0.5),
            hDivider.heightAnchor.constraint(equalToConstant: 0.5),
            d1.widthAnchor.constraint(equalToConstant: 0.5),
            d2.widthAnchor.constraint(equalToConstant: 0.5),
            vitCell.widthAnchor.constraint(equalTo: moyCell.widthAnchor),
            moyCell.widthAnchor.constraint(equalTo: toursCell.widthAnchor),
        ])
        return stack
    }

    /// One bottom-row stat cell: a value over an uppercase caption, centred.
    private func statCell(value: UILabel, valueColor: UIColor, caption: UILabel, captionText: String) -> UIView {
        value.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        value.textColor = valueColor
        value.textAlignment = .center
        value.text = "—"

        caption.text = captionText.uppercased()
        caption.font = .systemFont(ofSize: 10, weight: .semibold)
        caption.textColor = Palette.muted
        caption.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [value, caption])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 12, leading: 4, bottom: 12, trailing: 4)
        return stack
    }

    // MARK: - Dock behaviour

    private func toggleDock() {
        dockCollapsed.toggle()
        updateDockVisibility()
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        updateMapInset()
    }

    private func updateDockVisibility() {
        let idle = controller.state == .idle
        grabberButton.isHidden = idle
        idleCard.isHidden = !idle
        compactStats.isHidden = idle || !dockCollapsed
        expandedStats.isHidden = idle || dockCollapsed
    }

    private func updateMapInset() {
        view.layoutIfNeeded()
        let dockTop = bottomOverlay.frame.minY
        let inset = max(view.bounds.height - dockTop + 12, 200)
        mapView.setBottomInset(inset)
    }

    // MARK: - Map feeding

    private func seedMap() {
        let route = controller.routeCoordinates
        mapView.setRoute(route)
        if let last = route.last {
            mapView.setPosition(last)
            mapView.follow(last)
        }
        mapView.setMode(paused: controller.state == .paused, idle: controller.state == .idle)
        DispatchQueue.main.async { [weak self] in self?.updateMapInset() }
    }

    // MARK: - Buttons

    /// The sport picker: a flat white bordered chip (pull-down menu), matching the
    /// header chips — not a system material button.
    private func makeSportButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.background.backgroundColor = .white
        config.background.cornerRadius = 0
        config.background.strokeColor = Palette.border
        config.background.strokeWidth = 1
        config.baseForegroundColor = Palette.ink
        config.imagePadding = 7
        config.contentInsets = .init(top: 8, leading: 13, bottom: 8, trailing: 13)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = .systemFont(ofSize: 14, weight: .semibold)
            return attrs
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "sportPicker"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.12
        button.layer.shadowRadius = 3
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        return button
    }

    private func updateSportButton() {
        let sport = controller.sport
        sportButton.configuration?.title = sport.displayName
        sportButton.configuration?.image = UIImage(systemName: sport.symbolName)
        sportButton.menu = makeSportMenu()
        updateMetricCaptions()
        render(stats: controller.currentStats)
    }

    private func updateMetricCaptions() {
        let usesPace = controller.sport.usesPace
        vitCaption.text = (usesPace ? "Vit. /km" : "Vit. km/h").uppercased()
        moyCaption.text = (usesPace ? "Moy. /km" : "Moy. km/h").uppercased()
    }

    private func makeSportMenu() -> UIMenu {
        let current = controller.sport
        let actions = Sport.allCases.map { sport in
            UIAction(
                title: sport.displayName,
                image: UIImage(systemName: sport.symbolName),
                state: sport == current ? .on : .off
            ) { [weak self] _ in
                self?.controller.sport = sport
                self?.updateSportButton()
            }
        }
        return UIMenu(title: "Sport", children: actions)
    }

    /// A flat, sharp-cornered button (no system material). `filled` → the green
    /// primary; otherwise a white button with the given border/text colours.
    private func flatButton(title: String, titleColor: UIColor, background: UIColor, border: UIColor?, weight: UIFont.Weight, size: CGFloat) -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: size, weight: weight)
        button.backgroundColor = background
        button.layer.cornerRadius = 0
        if let border {
            button.layer.borderWidth = 1
            button.layer.borderColor = border.cgColor
        }
        button.adjustsImageWhenHighlighted = false
        return button
    }

    private func makeStartButton() -> UIButton {
        let button = flatButton(title: "Démarrer", titleColor: Palette.greenText, background: Palette.green,
                                border: nil, weight: .bold, size: 16)
        // The design gives Démarrer a soft green glow.
        button.layer.shadowColor = Palette.green.cgColor
        button.layer.shadowOpacity = 0.55
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
        button.addAction(UIAction { [weak self] _ in self?.controller.start() }, for: .primaryActionTriggered)
        return button
    }

    private func makeStopButton() -> UIButton {
        let button = flatButton(title: "Arrêter", titleColor: Palette.red, background: .white,
                                border: Palette.redBorder, weight: .semibold, size: 15)
        button.addAction(UIAction { [weak self] _ in self?.stop() }, for: .primaryActionTriggered)
        return button
    }

    private func makeOutlineButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = flatButton(title: title, titleColor: Palette.ink, background: .white,
                                border: Palette.border, weight: .semibold, size: 15)
        button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        return button
    }

    // MARK: - Actions

    private func togglePause() {
        controller.state == .recording ? controller.pause() : controller.resume()
    }

    private func markLap() {
        controller.markLap()
        render(stats: controller.currentStats)
    }

    private func close() {
        dismiss(animated: true)
    }

    private func stop() {
        let stats = controller.currentStats
        guard let session = controller.stop() else {
            dismiss(animated: true)
            return
        }
        guard !session.orderedPoints.isEmpty else {
            controller.discard(session)
            dismiss(animated: true)
            return
        }
        let review = RecordingReviewViewController(session: session, stats: stats)
        navigationController?.pushViewController(review, animated: true)
    }

    // MARK: - Rendering

    private func render(state: RecordingController.State) {
        switch state {
        case .idle:
            statePill.set(.idle)
            sportButton.isUserInteractionEnabled = true
            startButton.isHidden = false
            activeControls.isHidden = true
        case .recording:
            statePill.set(.recording)
            sportButton.isUserInteractionEnabled = false
            startButton.isHidden = true
            activeControls.isHidden = false
            lapButton.isHidden = false
            pauseResumeButton.setTitle("Pause", for: .normal)
        case .paused:
            statePill.set(.paused)
            sportButton.isUserInteractionEnabled = false
            startButton.isHidden = true
            activeControls.isHidden = false
            lapButton.isHidden = true
            pauseResumeButton.setTitle("Reprendre", for: .normal)
        }
        updateDockVisibility()
        mapView.setMode(paused: state == .paused, idle: state == .idle)
        DispatchQueue.main.async { [weak self] in self?.updateMapInset() }
    }

    private func render(stats: RecordingStats) {
        let usesPace = controller.sport.usesPace
        // One decimal for the dock distance (e.g. 104.6 km), matching the design.
        let distance = String(format: "%.1f", stats.distance / 1000)
        let time = dockElapsed(stats.elapsed)

        compactDistanceLabel.text = distance
        compactUnitLabel.text = "km"
        compactElapsedLabel.text = time.full
        compactSpeedLabel.attributedText = collapsedSpeedText(stats.currentSpeed, usesPace: usesPace)

        distanceValue.text = distance
        timeBig.text = time.big
        timeSmall.text = time.small

        vitValue.text = speedNumber(stats.currentSpeed, usesPace: usesPace)
        moyValue.text = speedNumber(stats.averageSpeed, usesPace: usesPace)
        toursValue.text = "\(max(controller.currentLap, 0))"
    }

    /// The collapsed dock's speed: the number in accent, the `km/h` unit smaller and
    /// muted (matching the design's two-weight collapsed speed).
    private func collapsedSpeedText(_ metersPerSecond: CLLocationSpeed, usesPace: Bool) -> NSAttributedString {
        let number: String
        let unit: String
        if usesPace {
            number = speedNumber(metersPerSecond, usesPace: true)
            unit = " /km"
        } else {
            number = String(format: "%.1f", max(metersPerSecond, 0) * 3.6)
            unit = " km/h"
        }
        let text = NSMutableAttributedString(
            string: number,
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold),
                .foregroundColor: accentColor,
            ]
        )
        text.append(NSAttributedString(
            string: unit,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: Palette.muted,
            ]
        ))
        return text
    }

    /// The value only (no unit) for the bottom stat cells: km/h for speed sports,
    /// pace (min/km, no suffix) for running.
    private func speedNumber(_ metersPerSecond: CLLocationSpeed, usesPace: Bool) -> String {
        if usesPace {
            let pace = RecordingFormatters.pace(metersPerSecond)
            return pace.replacingOccurrences(of: "/km", with: "")
        }
        return String(format: "%.1f", max(metersPerSecond, 0) * 3.6)
    }

    /// Elapsed split for the dock: `full` (collapsed) plus a `big` head + small
    /// `:ss` tail (expanded), matching the design's two-weight time (e.g. 4:38 / :20).
    private func dockElapsed(_ interval: TimeInterval) -> (full: String, big: String, small: String) {
        let total = max(Int(interval), 0)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let small = String(format: ":%02d", s)
        if h > 0 {
            return (String(format: "%d:%02d:%02d", h, m, s), String(format: "%d:%02d", h, m), small)
        }
        return (String(format: "%d:%02d", m, s), "\(m)", small)
    }
}

// MARK: - RecordingControllerDelegate

extension RecordingViewController: RecordingControllerDelegate {
    func recordingController(_ controller: RecordingController, didChangeAuthorization status: LocationRecorder.Status) {
        switch status {
        case .denied:
            gpsChip.setDenied()
            startButton.isEnabled = false
        case .authorized:
            gpsChip.clearDenied()
            startButton.isEnabled = true
        case .notDetermined:
            break
        }
    }

    func recordingController(_ controller: RecordingController, didChangeState state: RecordingController.State) {
        render(state: state)
    }

    func recordingController(_ controller: RecordingController, didUpdate stats: RecordingStats) {
        render(stats: stats)
    }

    func recordingController(_ controller: RecordingController, didReceiveFix location: CLLocation, pointCount: Int) {
        gpsChip.update(horizontalAccuracy: location.horizontalAccuracy)
        let coordinate = location.coordinate
        mapView.setPosition(coordinate)
        if controller.state == .recording {
            mapView.setRoute(controller.routeCoordinates)
        }
        mapView.follow(coordinate)
    }
}

// MARK: - StatusPillView

/// The state pill's contents (dot + uppercase word). Flat + coloured to match the
/// design; the backing white capsule is `pillContainer`. Pulses while recording.
private final class StatusPillView: UIView {
    enum State { case idle, recording, paused }

    private let dot = UIView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer.cornerRadius = 4.5

        label.font = .systemFont(ofSize: 12, weight: .bold)

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(_ state: State) {
        switch state {
        case .idle:
            isHidden = true
            stopPulsing()
        case .recording:
            isHidden = false
            apply(color: Palette.red, text: "Enregistrement")
            startPulsing()
        case .paused:
            isHidden = false
            apply(color: Palette.paused, text: "En pause")
            stopPulsing()
        }
    }

    private func apply(color: UIColor, text: String) {
        dot.backgroundColor = color
        label.attributedText = NSAttributedString(
            string: text.uppercased(),
            attributes: [.kern: 0.4, .foregroundColor: color]
        )
    }

    private func startPulsing() {
        guard dot.layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.28
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer.add(pulse, forKey: "pulse")
    }

    private func stopPulsing() {
        dot.layer.removeAnimation(forKey: "pulse")
    }
}

// MARK: - GPSChipView

/// A flat white bordered GPS chip: a signal-coloured dot + the current status. Not
/// a tinted material — matches the design's white chip.
private final class GPSChipView: UIView {
    var onTapWhenDenied: (() -> Void)?
    private var isDenied = false

    private let dot = UIView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        layer.borderWidth = 1
        layer.borderColor = Palette.border.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer.cornerRadius = 4

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Palette.ink
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        setSearching()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap() {
        guard isDenied else { return }
        onTapWhenDenied?()
    }

    func setSearching() {
        isDenied = false
        apply(text: "Recherche du GPS…", dot: Palette.muted, textColor: Palette.ink)
    }

    func setDenied() {
        isDenied = true
        apply(text: "Position refusée — Réglages", dot: Palette.red, textColor: Palette.red)
    }

    func clearDenied() {
        guard isDenied else { return }
        setSearching()
    }

    func update(horizontalAccuracy: CLLocationDistance) {
        guard !isDenied else { return }
        let green = Palette.green
        let amber = Palette.paused
        let (text, dotColor): (String, UIColor)
        switch horizontalAccuracy {
        case ..<0: (text, dotColor) = ("Recherche du GPS…", Palette.muted)
        case ..<8: (text, dotColor) = ("GPS bon", green)
        case ..<20: (text, dotColor) = ("GPS correct", green)
        case ..<50: (text, dotColor) = ("GPS moyen", amber)
        default: (text, dotColor) = ("GPS faible", amber)
        }
        apply(text: text, dot: dotColor, textColor: Palette.ink)
    }

    private func apply(text: String, dot dotColor: UIColor, textColor: UIColor) {
        label.text = text
        label.textColor = textColor
        dot.backgroundColor = dotColor
    }
}
