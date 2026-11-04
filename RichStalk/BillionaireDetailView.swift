// RichStalk — person detail.
// Two honest states, and nothing in between: either the person has aircraft
// with publicly documented registrations (shown with live status), or they
// do not, and the screen says so plainly instead of showing a fake position.

import SwiftUI

struct BillionaireDetailView: View {
    @EnvironmentObject private var trackingStore: TrackingStore
    let person: Billionaire

    var body: some View {
        List {
            Section {
                LabeledContent("Net worth", value: person.formattedNetWorth)
                if let rank = person.rank {
                    LabeledContent("Forbes 2025 rank", value: "#\(rank)")
                } else {
                    LabeledContent("Forbes 2025 rank", value: "Outside the top 206 snapshot")
                }
                LabeledContent("Country", value: person.country)
                LabeledContent("Source of wealth", value: person.source)
                Text(person.bio)
                    .font(.body)
            } header: {
                Text(person.name)
            }

            Section("Private jet") {
                if let aircraft = person.aircraft, !aircraft.isEmpty {
                    ForEach(aircraft) { jet in
                        AircraftRow(person: person, jet: jet)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "airplane.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No publicly tracked jet")
                            .font(.headline)
                        Text("No aircraft registration has been publicly documented for this person, or their flights are chartered or privacy-blocked. That does not mean they never fly privately — it means there is nothing honest to put on the map.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }

            Section("About live data") {
                Text("Live positions come from OpenSky ADS-B data and refresh about once a minute while the Map tab is open. Jets enrolled in privacy programs (LADD, PIA alternate codes) may not appear at all.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AircraftRow: View {
    @EnvironmentObject private var trackingStore: TrackingStore
    let person: Billionaire
    let jet: Aircraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(jet.registration)
                    .font(.headline)
                Spacer()
                Text(jet.icao24.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let model = jet.model {
                Text(model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(jet.hexSource == "published"
                 ? "ICAO24 code published independently."
                 : "ICAO24 code derived from the FAA N-number allocation (validated — see README).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            if let state = trackingStore.state(for: jet), state.hasPosition, !state.onGround {
                VStack(alignment: .leading, spacing: 2) {
                    if let callsign = state.callsign {
                        Text("Airborne · \(callsign)")
                            .font(.subheadline)
                    } else {
                        Text("Airborne")
                            .font(.subheadline)
                    }
                    HStack(spacing: 12) {
                        if let altitude = state.formattedAltitudeFeet {
                            Label(altitude, systemImage: "arrow.up")
                        }
                        if let speed = state.formattedSpeedKnots {
                            Label(speed, systemImage: "gauge.with.dots.needle.67percent")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else if let state = trackingStore.state(for: jet), state.onGround {
                Label("On the ground — no live position", systemImage: "airplane")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("No live signal right now", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            RecentFlightView(jet: jet)
        }
        .task {
            await trackingStore.loadRecentFlight(for: jet)
        }
    }
}

private struct RecentFlightView: View {
    @EnvironmentObject private var trackingStore: TrackingStore
    let jet: Aircraft

    var body: some View {
        if let flight = trackingStore.recentFlights[jet.icao24.lowercased()],
           let departure = flight.departureAirport,
           let arrival = flight.arrivalAirport {
            Label("\(departure) → \(arrival)", systemImage: "airplane.departure")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Most recent flight in the last 24 hours. Airport codes only — OpenSky does not name the airports.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
