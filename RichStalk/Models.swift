// RichStalk — data models.
// Net-worth figures come from the bundled Forbes 2025 snapshot (see Billionaires.json
// header and README.md). They are estimates from March 7, 2025 prices, not live figures.

import Foundation

/// One aircraft that may be live-tracked. `icao24` is the 24-bit Mode S address
/// OpenSky uses as its key. `hexSource` records whether that code was published
/// independently ("published") or derived from the FAA N-number allocation
/// algorithm ("computed") — see README.md for the validation of the algorithm.
struct Aircraft: Decodable, Identifiable, Hashable {
    var id: String { registration }
    let registration: String
    let icao24: String
    let model: String?
    let hexSource: String
}

/// One person on the list. `rank` is nil for the small "celebrity billionaires"
/// tranche, which comes from Forbes' 2025 celebrity-billionaire reporting rather
/// than the top-206 annual-list snapshot (see Billionaires.json header).
struct Billionaire: Decodable, Identifiable, Hashable {
    var id: String { name }
    let rank: Int?
    let name: String
    let netWorthBillions: Double
    let country: String
    let source: String
    let bio: String
    let aircraft: [Aircraft]?

    var hasTrackedJet: Bool { !(aircraft ?? []).isEmpty }

    var formattedNetWorth: String {
        if netWorthBillions.truncatingRemainder(dividingBy: 1) == 0 {
            return "$\(Int(netWorthBillions))B"
        }
        return String(format: "$%.1fB", netWorthBillions)
    }
}

struct BillionaireDataset: Decodable {
    let dataset: String
    let asOf: String
    let sourceNote: String
    let entries: [Billionaire]
}

enum BillionaireStore {
    static func load() -> (dataset: BillionaireDataset, people: [Billionaire]) {
        guard let url = Bundle.main.url(forResource: "Billionaires", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dataset = try? JSONDecoder().decode(BillionaireDataset.self, from: data) else {
            return (BillionaireDataset(dataset: "", asOf: "", sourceNote: "", entries: []), [])
        }
        return (dataset, dataset.entries)
    }

    /// Every aircraft in the dataset, paired with its owner, for the tracking layer.
    static func trackedAircraft(from people: [Billionaire]) -> [(owner: Billionaire, aircraft: Aircraft)] {
        people.flatMap { person in
            (person.aircraft ?? []).map { (owner: person, aircraft: $0) }
        }
    }
}
