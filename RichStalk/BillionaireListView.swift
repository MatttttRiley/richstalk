// RichStalk — the billionaire list.
// System List + .searchable. A filter limits the list to people with a
// publicly documented tracked jet, or to people without one. Net worths are
// a dated snapshot — the header says so, and the About screen explains why.

import SwiftUI

struct BillionaireListView: View {
    @State private var searchText = ""
    @State private var filter: ListFilter = .all
    @State private var showingAbout = false

    private let dataset: BillionaireDataset
    private let people: [Billionaire]

    init() {
        let loaded = BillionaireStore.load()
        dataset = loaded.dataset
        people = loaded.people
    }

    private enum ListFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case tracked = "Tracked jets"
        case untracked = "No tracked jet"
        var id: String { rawValue }
    }

    private var filteredPeople: [Billionaire] {
        var result = people
        switch filter {
        case .all: break
        case .tracked: result = result.filter { $0.hasTrackedJet }
        case .untracked: result = result.filter { !$0.hasTrackedJet }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.country.localizedCaseInsensitiveContains(query)
                || $0.source.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Net worths are a snapshot from \(dataset.asOf). Fortunes move daily with the markets — treat every figure as an estimate, not a live balance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredPeople) { person in
                    NavigationLink {
                        BillionaireDetailView(person: person)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(.headline)
                                Text("\(person.source) · \(person.country)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(person.formattedNetWorth)
                                    .font(.headline)
                                if person.hasTrackedJet {
                                    Label("Tracked", systemImage: "airplane")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No tracked jet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search billionaires")
            .navigationTitle("Billionaires")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Filter", selection: $filter) {
                        ForEach(ListFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Label("About this data", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView(dataset: dataset, totalPeople: people.count)
            }
        }
    }
}

private struct AboutView: View {
    let dataset: BillionaireDataset
    let totalPeople: Int

    var body: some View {
        NavigationStack {
            List {
                Section("What this list is") {
                    Text(dataset.sourceNote)
                    Text("This build lists \(totalPeople) billionaires: the top 206 of Forbes' 2025 annual list plus 5 additional billionaires from Forbes' 2025 celebrity-billionaire reporting who have publicly documented jets. The full 2025 Forbes list has 3,028 people — the remaining names are not in this bundle, and the app does not pretend otherwise.")
                }
                Section("Live tracking") {
                    Text("Live positions come from the OpenSky Network's free API, which reads aircraft ADS-B broadcasts. Only aircraft with a publicly documented registration and ICAO24 code are tracked.")
                    Text("A jet can disappear from the map for honest reasons: it is on the ground, it is outside receiver coverage, or its operator uses a privacy program (the FAA's LADD list or a PIA alternate code). A missing dot is never filled in with a guessed position.")
                    Text("A tracked jet is not proof its owner is on board. Aircraft fly empty, for maintenance, or with other passengers.")
                }
                Section("Accuracy") {
                    Text("Net worths are estimates from stock prices and exchange rates on March 7, 2025. They will already be out of date — that is expected, and the snapshot date is shown wherever a figure appears.")
                }
            }
            .navigationTitle("About RichStalk")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
