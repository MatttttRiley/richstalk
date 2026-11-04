// RichStalk — OpenSky Network client.
// Free, no API key, no secrets. Two endpoints only:
//   GET /api/states/all?icao24=<hex,hex>  — live positions (callsign, altitude, speed)
//   GET /api/flights/aircraft?icao24=<hex>&begin=<unix>&end=<unix> — recent flights
//     (departure/arrival airport codes) for the last 24 hours.
// OpenSky's anonymous tier is rate-limited, so callers must throttle (the app
// refreshes live states at most once every 60 seconds, and only while the Map
// tab is on screen). A 429 is surfaced as a plain-language error, never retried
// in a tight loop.

import Foundation

/// One live state vector, decoded from OpenSky's array-of-arrays format.
/// Field order follows https://opensky-network.org/apidoc/rest.html
struct OpenSkyState: Identifiable {
    var id: String { icao24 }
    let icao24: String
    let callsign: String?
    let originCountry: String?
    let longitude: Double?
    let latitude: Double?
    let baroAltitudeMeters: Double?
    let onGround: Bool
    let velocityMetersPerSecond: Double?
    let trueTrackDegrees: Double?
    let verticalRateMetersPerSecond: Double?

    var hasPosition: Bool { longitude != nil && latitude != nil }

    var formattedAltitudeFeet: String? {
        guard let meters = baroAltitudeMeters else { return nil }
        return "\(Int((meters * 3.28084).rounded())) ft"
    }

    var formattedSpeedKnots: String? {
        guard let metersPerSecond = velocityMetersPerSecond else { return nil }
        return "\(Int((metersPerSecond * 1.94384).rounded())) kt"
    }
}

/// The most recent flight found for an aircraft (used for origin/destination).
struct RecentFlight {
    let callsign: String?
    let departureAirport: String?
    let arrivalAirport: String?
    let firstSeen: Date
    let lastSeen: Date
}

enum OpenSkyError: LocalizedError {
    case network(Error)
    case rateLimited
    case server(status: Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .network: return "Could not reach OpenSky. Check your connection and try again."
        case .rateLimited: return "OpenSky rate limit reached. Live updates will resume shortly — try Refresh in a minute."
        case .server: return "OpenSky returned an unexpected response. Try again shortly."
        case .noData: return "OpenSky returned no data for this aircraft."
        }
    }
}

enum OpenSkyService {
    private static let baseURL = URL(string: "https://opensky-network.org/api")!

    /// Fetches live states for the given ICAO24 codes in a single request.
    /// Returns only rows that decoded cleanly; aircraft with no live signal
    /// simply do not appear in the result (callers treat absence as "no live
    /// signal right now", never as a position).
    static func fetchStates(icao24s: [String]) async throws -> [OpenSkyState] {
        guard !icao24s.isEmpty else { return [] }
        var components = URLComponents(url: baseURL.appendingPathComponent("states/all"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "icao24", value: icao24s.map { $0.lowercased() }.joined(separator: ","))]
        guard let url = components.url else { throw OpenSkyError.noData }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenSkyError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw OpenSkyError.noData }
        if http.statusCode == 429 { throw OpenSkyError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw OpenSkyError.server(status: http.statusCode) }
        return try decodeStates(data)
    }

    /// Fetches the most recent flight in the last 24 hours for one aircraft,
    /// for origin/destination display. Returns nil when there is no flight in
    /// the window — that is a normal outcome, not an error.
    static func fetchMostRecentFlight(icao24: String) async throws -> RecentFlight? {
        let now = Date()
        let begin = Int(now.addingTimeInterval(-24 * 60 * 60).timeIntervalSince1970)
        let end = Int(now.timeIntervalSince1970)
        var components = URLComponents(url: baseURL.appendingPathComponent("flights/aircraft"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "icao24", value: icao24.lowercased()),
            URLQueryItem(name: "begin", value: String(begin)),
            URLQueryItem(name: "end", value: String(end)),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenSkyError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 429 { throw OpenSkyError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { return nil }
        struct FlightRow: Decodable {
            let callsign: String?
            let firstSeen: Int
            let lastSeen: Int
            let estDepartureAirport: String?
            let estArrivalAirport: String?
        }
        guard let rows = try? JSONDecoder().decode([FlightRow].self, from: data),
              let latest = rows.max(by: { $0.lastSeen < $1.lastSeen }) else {
            return nil
        }
        return RecentFlight(
            callsign: latest.callsign?.trimmingCharacters(in: .whitespaces),
            departureAirport: latest.estDepartureAirport,
            arrivalAirport: latest.estArrivalAirport,
            firstSeen: Date(timeIntervalSince1970: TimeInterval(latest.firstSeen)),
            lastSeen: Date(timeIntervalSince1970: TimeInterval(latest.lastSeen))
        )
    }

    // MARK: - Decoding (array-of-arrays format)

    private struct StatesResponse: Decodable {
        let states: [StateRow]?
    }

    private struct StateRow: Decodable {
        let icao24: String
        let callsign: String?
        let originCountry: String?
        let longitude: Double?
        let latitude: Double?
        let baroAltitude: Double?
        let onGround: Bool
        let velocity: Double?
        let trueTrack: Double?
        let verticalRate: Double?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            icao24 = try container.decode(String.self)
            callsign = try container.decodeIfPresent(String.self)?.trimmingCharacters(in: .whitespaces)
            originCountry = try container.decodeIfPresent(String.self)
            _ = try container.decodeIfPresent(Int.self) // time_position
            _ = try container.decodeIfPresent(Int.self) // last_contact
            longitude = try container.decodeIfPresent(Double.self)
            latitude = try container.decodeIfPresent(Double.self)
            baroAltitude = try container.decodeIfPresent(Double.self)
            onGround = (try? container.decode(Bool.self)) ?? false
            velocity = try container.decodeIfPresent(Double.self)
            trueTrack = try container.decodeIfPresent(Double.self)
            verticalRate = try container.decodeIfPresent(Double.self)
            // Remaining fields (sensors, geo altitude, squawk, spi, source,
            // category) are intentionally not consumed.
        }
    }

    private static func decodeStates(_ data: Data) throws -> [OpenSkyState] {
        let response = try JSONDecoder().decode(StatesResponse.self, from: data)
        return (response.states ?? []).map { row in
            OpenSkyState(
                icao24: row.icao24.lowercased(),
                callsign: row.callsign?.isEmpty == true ? nil : row.callsign,
                originCountry: row.originCountry,
                longitude: row.longitude,
                latitude: row.latitude,
                baroAltitudeMeters: row.baroAltitude,
                onGround: row.onGround,
                velocityMetersPerSecond: row.velocity,
                trueTrackDegrees: row.trueTrack,
                verticalRateMetersPerSecond: row.verticalRate
            )
        }
    }
}
