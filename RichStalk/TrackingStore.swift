// RichStalk — live-tracking state.
// Refreshes at most once every 60 seconds, only while tracking is active
// (the Map tab drives start/stop). Absence of a state for an aircraft means
// "no live signal right now" — the app never invents or replays a position.

import Foundation

@MainActor
final class TrackingStore: ObservableObject {
    /// Live states keyed by lowercase ICAO24.
    @Published private(set) var states: [String: OpenSkyState] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    /// Recent-flight info (origin/destination) keyed by lowercase ICAO24.
    @Published private(set) var recentFlights: [String: RecentFlight] = [:]

    /// Trail history for this map session only, keyed by lowercase ICAO24.
    /// Each point is a position actually received from OpenSky — never
    /// interpolated, predicted, or carried over from a previous session.
    /// Capped at 24 points per aircraft; only airborne positions are kept.
    @Published private(set) var trails: [String: [(latitude: Double, longitude: Double)]] = [:]

    private var refreshTask: Task<Void, Never>?

    var trackedAircraft: [(owner: Billionaire, aircraft: Aircraft)] = []

    func startTracking(aircraft: [(owner: Billionaire, aircraft: Aircraft)]) {
        trackedAircraft = aircraft
        // Fresh session, fresh trails: yesterday's positions are not a
        // route for today's flight.
        trails = [:]
        stopTracking()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
    }

    func stopTracking() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        let codes = trackedAircraft.map { $0.aircraft.icao24.lowercased() }
        guard !codes.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await OpenSkyService.fetchStates(icao24s: codes)
            var next: [String: OpenSkyState] = [:]
            for state in fetched { next[state.icao24] = state }
            states = next
            // Record trail points only from positions actually received
            // in this refresh, and only for airborne aircraft. A repeated
            // sample at (nearly) the same spot adds no point, so a parked
            // or slow sample does not inflate the trail.
            for state in fetched where state.hasPosition && !state.onGround {
                guard let latitude = state.latitude,
                      let longitude = state.longitude else { continue }
                var trail = trails[state.icao24] ?? []
                let last = trail.last
                if last == nil
                    || abs(last!.latitude - latitude) > 0.0005
                    || abs(last!.longitude - longitude) > 0.0005 {
                    trail.append((latitude: latitude, longitude: longitude))
                    if trail.count > 24 {
                        trail.removeFirst(trail.count - 24)
                    }
                    trails[state.icao24] = trail
                }
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch let error as OpenSkyError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Live tracking is unavailable right now."
        }
    }

    func state(for aircraft: Aircraft) -> OpenSkyState? {
        states[aircraft.icao24.lowercased()]
    }

    /// Loads origin/destination for one aircraft (last 24h flight). Called
    /// from the detail screen only, to conserve OpenSky's anonymous quota.
    func loadRecentFlight(for aircraft: Aircraft) async {
        let key = aircraft.icao24.lowercased()
        guard recentFlights[key] == nil else { return }
        do {
            if let flight = try await OpenSkyService.fetchMostRecentFlight(icao24: key) {
                recentFlights[key] = flight
            }
        } catch {
            // Origin/destination is best-effort; the live state stands alone.
        }
    }
}
