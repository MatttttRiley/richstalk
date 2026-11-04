// RichStalk — tracking map.
// MapKit via a UIViewRepresentable wrapper so the map type can switch
// between standard and satellite on iOS 16 (SwiftUI's mapStyle needs iOS 17).
// Pins are live OpenSky positions only; an aircraft with no live signal gets
// no pin at all. The map never shows a guessed or stale position as live,
// and it never interpolates between OpenSky samples: when a new sample
// arrives (about once a minute), the existing pin glides to that measured
// position instead of being removed and re-added. Between samples the pin
// sits still, because that is what was actually measured.
// Heading comes from OpenSky's true-track field when it is broadcast;
// when it is not, the aircraft gets a plain pin instead of a guessed heading.
// A trail, when shown, is only positions actually received during this map
// session, for the selected aircraft only — never a predicted route.

import SwiftUI
import UIKit
import MapKit

struct TrackingMapView: View {
    @EnvironmentObject private var trackingStore: TrackingStore
    @State private var mapType: MapTypeOption = .standard
    @State private var people: [Billionaire] = []
    @State private var selectedRegistration: String?
    @State private var fitAllRequest = 0

    private enum MapTypeOption: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case satellite = "Satellite"
        var id: String { rawValue }
    }

    private var tracked: [(owner: Billionaire, aircraft: Aircraft)] {
        BillionaireStore.trackedAircraft(from: people)
    }

    private var liveAircraft: [(owner: Billionaire, aircraft: Aircraft, state: OpenSkyState)] {
        tracked.compactMap { item in
            guard let state = trackingStore.state(for: item.aircraft),
                  state.hasPosition, !state.onGround else { return nil }
            return (owner: item.owner, aircraft: item.aircraft, state: state)
        }
    }

    private var selectedItem: (owner: Billionaire, aircraft: Aircraft, state: OpenSkyState)? {
        guard let registration = selectedRegistration else { return nil }
        return liveAircraft.first { $0.aircraft.registration == registration }
    }

    /// Trail for the selected aircraft only, from positions actually
    /// received during this map session (see TrackingStore).
    private var selectedTrail: [CLLocationCoordinate2D] {
        guard let item = selectedItem,
              let trail = trackingStore.trails[item.aircraft.icao24.lowercased()] else {
            return []
        }
        return trail.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var trailPointCount: Int {
        guard let item = selectedItem else { return 0 }
        return trackingStore.trails[item.aircraft.icao24.lowercased()]?.count ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Map type", selection: $mapType) {
                    ForEach(MapTypeOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                AircraftMapView(
                    mapType: mapType == .standard ? .standard : .satellite,
                    liveAircraft: liveAircraft,
                    selectedTrail: selectedTrail,
                    fitAllRequest: fitAllRequest,
                    selectedRegistration: $selectedRegistration
                )

                List {
                    if let error = trackingStore.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let updated = trackingStore.lastUpdated {
                        Text("Last updated \(updated, style: .time) · refreshes about once a minute")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if liveAircraft.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "airplane.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No jets airborne right now")
                                .font(.headline)
                            Text("None of the documented jets are broadcasting a live position at the moment. They may be on the ground, outside receiver coverage, or privacy-blocked. Pull to refresh or tap Refresh to check again.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ForEach(liveAircraft, id: \.aircraft.registration) { item in
                            Button {
                                selectedRegistration = item.aircraft.registration
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.owner.name)
                                            .font(.headline)
                                        Text("\(item.aircraft.registration) · \(item.state.callsign ?? "No callsign")")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 12) {
                                            if let altitude = item.state.formattedAltitudeFeet {
                                                Text(altitude)
                                            }
                                            if let speed = item.state.formattedSpeedKnots {
                                                Text(speed)
                                            }
                                            if let heading = item.state.trueTrackDegrees {
                                                Text("Heading \(Int(heading.rounded()))°")
                                            }
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedRegistration == item.aircraft.registration {
                                        Image(systemName: "location.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowBackground(
                                selectedRegistration == item.aircraft.registration
                                    ? Color.accentColor.opacity(0.15) : nil
                            )
                        }
                    }

                    Section("Tracked, but no live signal") {
                        ForEach(tracked.filter { trackingStore.state(for: $0.aircraft)?.hasPosition != true }, id: \.aircraft.registration) { item in
                            Text("\(item.owner.name) — \(item.aircraft.registration)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Tracking Map")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Show all") {
                        if !liveAircraft.isEmpty { fitAllRequest += 1 }
                    }
                    .disabled(liveAircraft.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await trackingStore.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task {
                people = BillionaireStore.load().people
                trackingStore.startTracking(aircraft: BillionaireStore.trackedAircraft(from: people))
            }
            .onReceive(trackingStore.$lastUpdated) { _ in
                // A refresh dropped the selected aircraft (signal lost or
                // landed): stop following it rather than showing stale data.
                // onReceive (not the newer onChange form) keeps this iOS 16
                // compatible without a deprecation warning.
                if selectedItem == nil { selectedRegistration = nil }
            }
            .onDisappear {
                trackingStore.stopTracking()
                selectedRegistration = nil
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedRegistration != nil },
                    set: { if !$0 { selectedRegistration = nil } }
                )
            ) {
                if let item = selectedItem {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.owner.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("\(item.aircraft.registration) · \(item.aircraft.model ?? "Model not listed")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Divider()

                            flightStatRow(label: "Callsign", value: item.state.callsign ?? "No callsign broadcast")
                            flightStatRow(label: "Altitude", value: item.state.formattedAltitudeFeet ?? "—")
                            flightStatRow(label: "Speed", value: item.state.formattedSpeedKnots ?? "—")
                            if let heading = item.state.trueTrackDegrees {
                                flightStatRow(label: "Heading", value: "\(Int(heading.rounded()))°")
                            } else {
                                flightStatRow(label: "Heading", value: "Not broadcast")
                            }
                            flightStatRow(label: "Status", value: flightStatus(for: item.state))
                            if let updated = trackingStore.lastUpdated {
                                flightStatRow(label: "Last updated", value: updated.formatted(date: .omitted, time: .shortened))
                            }

                            Divider()

                            if trailPointCount >= 2 {
                                Text("Trail: \(trailPointCount) positions actually received during this map session. No route is predicted.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No trail yet — positions will appear on the map as they are received, about once a minute.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Stop Following") {
                                selectedRegistration = nil
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                    .presentationDetents([.medium, .large])
                } else {
                    Text("That flight is no longer live.")
                        .padding()
                }
            }
        }
    }

    private func flightStatus(for state: OpenSkyState) -> String {
        if state.onGround { return "On the ground" }
        guard let vertical = state.verticalRateMetersPerSecond else { return "Airborne" }
        if vertical > 1.0 { return "Airborne · Climbing" }
        if vertical < -1.0 { return "Airborne · Descending" }
        return "Airborne · Level"
    }

    private func flightStatRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - MapKit wrapper

/// One live aircraft on the map. `coordinate` is dynamic so MapKit can
/// animate it when a new OpenSky sample arrives, instead of the annotation
/// being removed and re-added.
private final class AircraftAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    let registration: String
    let ownerName: String
    var heading: Double?
    var title: String?
    var subtitle: String?

    init(
        coordinate: CLLocationCoordinate2D,
        registration: String,
        ownerName: String,
        heading: Double?,
        title: String?,
        subtitle: String?
    ) {
        self.coordinate = coordinate
        self.registration = registration
        self.ownerName = ownerName
        self.heading = heading
        self.title = title
        self.subtitle = subtitle
    }
}

/// One annotation view that can show either a heading-rotated plane or a
/// plain pin, without being recreated when the mode changes.
private final class AircraftAnnotationView: MKAnnotationView {
    private let planeImageView = UIImageView()
    private let pinImageView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        canShowCallout = false
        planeImageView.frame = bounds
        planeImageView.contentMode = .scaleAspectFit
        addSubview(planeImageView)
        pinImageView.frame = bounds
        pinImageView.contentMode = .scaleAspectFit
        pinImageView.tintColor = .systemRed
        pinImageView.image = UIImage(systemName: "mappin.circle.fill")
        addSubview(pinImageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the plane, rotated to the broadcast heading, or the pin when
    /// no heading is broadcast. Never invents a heading.
    func configure(heading: Double?) {
        if let heading {
            planeImageView.image = Self.planeImage(heading: heading)
            planeImageView.isHidden = false
            pinImageView.isHidden = true
            centerOffset = .zero
        } else {
            planeImageView.isHidden = true
            pinImageView.isHidden = false
            centerOffset = CGPoint(x: 0, y: -16)
        }
    }

    /// A simple jet silhouette pointing up (north), rotated to the given
    /// heading in degrees. Drawn, not taken from an SF Symbol, so its nose
    /// direction is exactly up at heading 0 rather than an angled symbol.
    static func planeImage(heading: Double) -> UIImage {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: CGFloat(heading * .pi / 180))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: -16))
            path.addLine(to: CGPoint(x: 5, y: -4))
            path.addLine(to: CGPoint(x: 15, y: 9))
            path.addLine(to: CGPoint(x: 5, y: 6))
            path.addLine(to: CGPoint(x: 3, y: 15))
            path.addLine(to: CGPoint(x: -3, y: 15))
            path.addLine(to: CGPoint(x: -5, y: 6))
            path.addLine(to: CGPoint(x: -15, y: 9))
            path.addLine(to: CGPoint(x: -5, y: -4))
            path.close()
            UIColor.white.setFill()
            path.fill()
            UIColor.black.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}

private struct AircraftMapView: UIViewRepresentable {
    let mapType: MKMapType
    let liveAircraft: [(owner: Billionaire, aircraft: Aircraft, state: OpenSkyState)]
    let selectedTrail: [CLLocationCoordinate2D]
    let fitAllRequest: Int
    @Binding var selectedRegistration: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedRegistration: $selectedRegistration)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        // Rotation is off so a plane rotated to its true track stays true
        // to north; with a rotated map the heading would read wrong.
        mapView.isRotateEnabled = false
        // Default framing: continental United States, where most tracked
        // aircraft operate. The map is only reframed on an explicit
        // selection or "Show all" tap — never on every refresh, so panning
        // is not fought by incoming samples.
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        let coordinator = context.coordinator

        // Sync annotations in place: update existing ones, add newly live
        // ones, remove ones that lost signal. Never remove-and-re-add all.
        var existingByRegistration: [String: AircraftAnnotation] = [:]
        for annotation in mapView.annotations.compactMap({ $0 as? AircraftAnnotation }) {
            existingByRegistration[annotation.registration] = annotation
        }
        var seen = Set<String>()
        for item in liveAircraft {
            guard let latitude = item.state.latitude,
                  let longitude = item.state.longitude else { continue }
            let registration = item.aircraft.registration
            seen.insert(registration)
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let title = "\(item.owner.name) · \(registration)"
            var subtitleParts: [String] = []
            if let callsign = item.state.callsign { subtitleParts.append(callsign) }
            if let altitude = item.state.formattedAltitudeFeet { subtitleParts.append(altitude) }
            if let speed = item.state.formattedSpeedKnots { subtitleParts.append(speed) }
            let subtitle = subtitleParts.joined(separator: " · ")
            if let annotation = existingByRegistration[registration] {
                annotation.title = title
                annotation.subtitle = subtitle
                annotation.heading = item.state.trueTrackDegrees
                if annotation.coordinate.latitude != coordinate.latitude
                    || annotation.coordinate.longitude != coordinate.longitude {
                    UIView.animate(
                        withDuration: 1.5,
                        delay: 0,
                        options: [.curveEaseInOut, .allowUserInteraction]
                    ) {
                        annotation.coordinate = coordinate
                    }
                }
                if let view = mapView.view(for: annotation) as? AircraftAnnotationView {
                    view.configure(heading: annotation.heading)
                }
            } else {
                let annotation = AircraftAnnotation(
                    coordinate: coordinate,
                    registration: registration,
                    ownerName: item.owner.name,
                    heading: item.state.trueTrackDegrees,
                    title: title,
                    subtitle: subtitle
                )
                mapView.addAnnotation(annotation)
            }
        }
        for (registration, annotation) in existingByRegistration where !seen.contains(registration) {
            mapView.removeAnnotation(annotation)
        }

        // Selection + following. The map only recentres on selection change
        // (zoomed to the aircraft) and then keeps it centred, preserving the
        // user's zoom, as it moves. Clearing the selection deselects the pin.
        if let selected = selectedRegistration {
            let annotation = mapView.annotations
                .compactMap { $0 as? AircraftAnnotation }
                .first { $0.registration == selected }
            if let annotation {
                if (mapView.selectedAnnotations.first as? AircraftAnnotation)?.registration != selected {
                    mapView.selectAnnotation(annotation, animated: false)
                }
                if coordinator.lastCenteredRegistration != selected {
                    coordinator.lastCenteredRegistration = selected
                    mapView.setRegion(
                        MKCoordinateRegion(
                            center: annotation.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
                        ),
                        animated: true
                    )
                } else {
                    let centre = mapView.region.center
                    if abs(centre.latitude - annotation.coordinate.latitude) > 0.0005
                        || abs(centre.longitude - annotation.coordinate.longitude) > 0.0005 {
                        mapView.setRegion(
                            MKCoordinateRegion(center: annotation.coordinate, span: mapView.region.span),
                            animated: true
                        )
                    }
                }
            } else {
                coordinator.lastCenteredRegistration = nil
            }
        } else {
            coordinator.lastCenteredRegistration = nil
            for annotation in mapView.selectedAnnotations.compactMap({ $0 as? AircraftAnnotation }) {
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        // One-shot "Show all": frame every live aircraft, with padding.
        if fitAllRequest != coordinator.lastFitRequest {
            coordinator.lastFitRequest = fitAllRequest
            let coordinates = liveAircraft.compactMap { item -> CLLocationCoordinate2D? in
                guard let latitude = item.state.latitude,
                      let longitude = item.state.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            if !coordinates.isEmpty {
                let minLatitude = coordinates.map(\.latitude).min()!
                let maxLatitude = coordinates.map(\.latitude).max()!
                let minLongitude = coordinates.map(\.longitude).min()!
                let maxLongitude = coordinates.map(\.longitude).max()!
                let spanLatitude = max((maxLatitude - minLatitude) * 1.4, 1.0)
                let spanLongitude = max((maxLongitude - minLongitude) * 1.4, 1.0)
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: (minLatitude + maxLatitude) / 2,
                            longitude: (minLongitude + maxLongitude) / 2
                        ),
                        span: MKCoordinateSpan(latitudeDelta: spanLatitude, longitudeDelta: spanLongitude)
                    ),
                    animated: true
                )
            }
        }

        // Trail overlay for the selected aircraft only. The polyline itself
        // is redrawn on each update; it is a line, not a pin, and its points
        // are only positions actually received (see TrackingStore).
        mapView.removeOverlays(mapView.overlays.filter { $0 is MKPolyline })
        if selectedRegistration != nil, selectedTrail.count >= 2 {
            // MKPolyline copies the coordinates on init, so building it
            // inside the buffer-pointer scope is safe.
            let polyline = selectedTrail.withUnsafeBufferPointer { buffer in
                MKPolyline(coordinates: buffer.baseAddress!, count: selectedTrail.count)
            }
            mapView.addOverlay(polyline)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var selectedRegistration: Binding<String?>
        var lastCenteredRegistration: String?
        var lastFitRequest = 0

        init(selectedRegistration: Binding<String?>) {
            self.selectedRegistration = selectedRegistration
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let aircraftAnnotation = annotation as? AircraftAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "aircraft") as? AircraftAnnotationView)
                ?? AircraftAnnotationView(annotation: aircraftAnnotation, reuseIdentifier: "aircraft")
            view.annotation = aircraftAnnotation
            view.configure(heading: aircraftAnnotation.heading)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? AircraftAnnotation {
                selectedRegistration.wrappedValue = annotation.registration
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if let annotation = view.annotation as? AircraftAnnotation,
               selectedRegistration.wrappedValue == annotation.registration {
                selectedRegistration.wrappedValue = nil
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemTeal
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
