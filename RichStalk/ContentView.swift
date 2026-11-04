// RichStalk — root tabs. System TabView, one NavigationStack per tab,
// system labels and symbols, no custom chrome, no forced appearance.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BillionaireListView()
                .tabItem {
                    Label("Billionaires", systemImage: "list.bullet")
                }

            TrackingMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
        }
    }
}
