// RichStalk — Billionaire Jet Tracker
// App entry point. System appearance only: no forced color scheme anywhere in the app.

import SwiftUI

@main
struct RichStalkApp: App {
    @StateObject private var trackingStore = TrackingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(trackingStore)
        }
    }
}
