// PROTOTYPE — throwaway (wayfinder #21). The planner screen with its three
// switchable variants: handle style, sheet style and insertion style. The
// switcher pill at the top is prototype chrome, not part of the design.
import Charts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PlannerPrototype {
    static func present(from presenter: UIViewController, onSaved: @escaping (URL) -> Void) {
        var host: UIHostingController<PlannerPrototypeScreen>!
        let screen = PlannerPrototypeScreen(
            onClose: { host?.dismiss(animated: true) },
            onSaved: { url in host?.dismiss(animated: true) { onSaved(url) } }
        )
        host = UIHostingController(rootView: screen)
        host.modalPresentationStyle = .fullScreen
        presenter.present(host, animated: true)
    }
}

struct PlannerPrototypeScreen: View {
    let onClose: () -> Void
    let onSaved: (URL) -> Void

    @State private var model = PlannerModel()
    @State private var projection = MapProjection()
    @State private var showDetails = false
    @State private var showImporter = false
    @State private var saving = false
    @State private var detent: PresentationDetent = .height(130)

    private var gpxTypes: [UTType] { [UTType(filenameExtension: "gpx") ?? .xml, .xml] }

    var body: some View {
        ZStack {
            PlannerMapView(model: model, projection: projection, bottomInset: model.sheetStyle == .card ? 150 : 150)
                .accessibilityIdentifier("planner-map")
                .accessibilityLabel("Carte, \(model.waypoints.count) points")
            if model.handleStyle == .overlay { handles }
        }
        .coordinateSpace(name: "map")
        .ignoresSafeArea()
        .overlay(alignment: .top) { topChrome }
        .overlay(alignment: .bottom) { if model.sheetStyle == .card { card } }
        .sheet(isPresented: .constant(model.sheetStyle == .detents)) {
            details(compactHeader: true)
                .presentationDetents([.height(130), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .fileImporter(isPresented: $showImporter, allowedContentTypes: gpxTypes) { importResult($0) }
        }
        .sheet(isPresented: $showDetails) {
            details(compactHeader: false)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .fileImporter(isPresented: $showImporter, allowedContentTypes: gpxTypes) { importResult($0) }
        }
    }

    // MARK: Overlay handles (variant "Poignées app")

    private var handles: some View {
        ForEach(Array(model.waypoints.enumerated()), id: \.offset) { i, w in
            let moving = model.dragPreview?.movingIndex == i ? model.dragPreview?.coordinate : nil
            HandleDot(index: i, selected: model.selectedIndex == i, lifted: moving != nil)
                .position(projection.point(moving ?? w))
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("map"))
                        .onChanged { v in
                            if model.dragPreview == nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            model.dragPreview = DragPreview(movingIndex: i, insertAt: nil, coordinate: projection.coordinate(at: v.location))
                        }
                        .onEnded { v in
                            model.dragPreview = nil
                            model.move(i, to: projection.coordinate(at: v.location))
                        }
                )
                .onTapGesture { model.selectedIndex = model.selectedIndex == i ? nil : i }
                .accessibilityIdentifier("planner-waypoint-\(i + 1)")
        }
    }

    // MARK: Top chrome

    private var topChrome: some View {
        VStack(spacing: 8) {
            HStack {
                circleButton("xmark", id: "planner-close", action: onClose)
                Spacer()
                circleButton("arrow.uturn.backward", id: "planner-undo", disabled: !model.canUndo) { model.undo() }
                circleButton("arrow.uturn.forward", id: "planner-redo", disabled: !model.canRedo) { model.redo() }
                circleButton("trash", id: "planner-clear", disabled: model.waypoints.isEmpty) { model.clear() }
            }
            if let i = model.selectedIndex {
                Button(role: .destructive) { model.remove(i) } label: {
                    Label("Supprimer le point \(i + 1)", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .accessibilityIdentifier("planner-delete-selected")
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.red, in: Capsule())
                    .onTapGesture { model.error = nil }
            }
            Spacer()
            if model.waypoints.isEmpty {
                Text("Appui long sur la carte pour placer le départ")
                    .font(.footnote).padding(10).background(.regularMaterial, in: Capsule())
            }
            switcher
        }
        .padding(.horizontal, 16)
        .padding(.bottom, model.sheetStyle == .card ? 150 : 140)
    }

    private func circleButton(_ symbol: String, id: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .disabled(disabled)
        .accessibilityIdentifier(id)
    }

    /// Prototype-only: flips the three variants and shows the model state.
    private var switcher: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Menu(model.handleStyle.rawValue) { Picker("", selection: $model.handleStyle) { ForEach(HandleStyle.allCases) { Text($0.rawValue).tag($0) } } }
                Menu(model.insertStyle.rawValue) { Picker("", selection: $model.insertStyle) { ForEach(InsertStyle.allCases) { Text($0.rawValue).tag($0) } } }
                Menu(model.sheetStyle.rawValue) { Picker("", selection: $model.sheetStyle) { ForEach(SheetStyle.allCases) { Text($0.rawValue).tag($0) } } }
            }
            .font(.caption2.weight(.bold))
            .tint(.yellow)
            Text(model.stateLine).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("planner-prototype-switcher")
    }

    // MARK: Variant "Carte flottante"

    private var card: some View {
        HStack(spacing: 12) {
            stats
            Spacer()
            Button { showDetails = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 40, height: 40) }
                .accessibilityIdentifier("planner-details")
            saveButton
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    // MARK: Shared details (sheet content)

    private func details(compactHeader: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    stats
                    Spacer()
                    if compactHeader { saveButton }
                }
                TextField("Nom de l’itinéraire", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("planner-name")
                Picker("Sport", selection: $model.sport) {
                    ForEach(PlannerModel.sports, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.menu)
                if model.elevationSamples.count > 1 {
                    Chart(Array(model.elevationSamples.enumerated()), id: \.offset) { _, s in
                        AreaMark(x: .value("km", s.0 / 1000), y: .value("m", s.1)).foregroundStyle(.orange.opacity(0.3))
                        LineMark(x: .value("km", s.0 / 1000), y: .value("m", s.1)).foregroundStyle(.orange)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 120)
                }
                Button { showImporter = true } label: { Label("Importer un GPX", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("planner-import-gpx")
                if !compactHeader { saveButton }
            }
            .padding(20)
        }
    }

    private var stats: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading) {
                Text(model.distanceMeters.map { String(format: "%.1f km", $0 / 1000) } ?? "— km").font(.title3.weight(.bold))
                Text("Distance").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading) {
                Text(model.elevationGainMeters.map { "\(Int($0)) m" } ?? "— m").font(.title3.weight(.bold))
                Text("D+").font(.caption).foregroundStyle(.secondary)
            }
            if model.isRouting { ProgressView() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planner-stats")
    }

    private var saveButton: some View {
        Button {
            saving = true
            Task {
                if let url = await model.save() { onSaved(url) }
                saving = false
            }
        } label: {
            Text("Enregistrer").font(.headline).padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.waypoints.count < 2 || saving)
        .accessibilityIdentifier("planner-save")
    }

    private func importResult(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task { await model.importGpx(url) }
    }
}

private struct HandleDot: View {
    let index: Int
    let selected: Bool
    let lifted: Bool

    var body: some View {
        let start = index == 0
        Text("\(index + 1)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(start ? Color.orange : .white)
            .frame(width: 26, height: 26)
            .background(start ? Color.white : .orange, in: Circle())
            .overlay(Circle().stroke(selected ? Color.blue : (start ? .orange : .white), lineWidth: selected ? 4 : 3))
            .shadow(radius: lifted ? 6 : 2)
            .scaleEffect(lifted ? 1.35 : 1)
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }
}
