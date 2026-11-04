// RichStalk — tracking map.
// MapKit via a UIViewRepresentable wrapper so the map type can switch
// between standard and satellite on iOS 16 (SwiftUI's mapStyle needs iOS 17).
// Pins are live OpenSky positions only; an aircraft with no live signal gets
// no pin at all. The map never shows a guessed or stale position as live.

import SwiftUI
import MapKit

struct TrackingMapView: View {
    @EnvironmentObject private var trackingStore: TrackingStore
    @State private var mapType: MapTypeOption = .standard
    @State private var people: [Billionaire] = []

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
                    liveAircraft: liveAircraft
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
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
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
            .onDisappear {
                trackingStore.stopTracking()
            }
        }
    }
}

// MARK: - MapKit wrapper

private struct AircraftMapView: UIViewRepresentable {
    let mapType: MKMapType
    let liveAircraft: [(owner: Billionaire, aircraft: Aircraft, state: OpenSkyState)]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.showsUserLocation = false
        // Default framing: continental United States, where most tracked
        // aircraft operate. Reframed to the first live aircraft below.
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType
        mapView.removeAnnotations(mapView.annotations)
        var annotations: [MKPointAnnotation] = []
        for item in liveAircraft {
            guard let latitude = item.state.latitude, let longitude = item.state.longitude else { continue }
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            annotation.title = "\(item.owner.name) · \(item.aircraft.registration)"
            var subtitleParts: [String] = []
            if let callsign = item.state.callsign { subtitleParts.append(callsign) }
            if let altitude = item.state.formattedAltitudeFeet { subtitleParts.append(altitude) }
            if let speed = item.state.formattedSpeedKnots { subtitleParts.append(speed) }
            annotation.subtitle = subtitleParts.joined(separator: " · ")
            annotations.append(annotation)
        }
        mapView.addAnnotations(annotations)
        if let first = liveAircraft.first,
           let latitude = first.state.latitude,
           let longitude = first.state.longitude {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
                ),
                animated: true
            )
        }
    }
}
