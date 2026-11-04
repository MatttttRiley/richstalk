# RichStalk — Billionaire Jet Tracker

A SwiftUI iOS app (iOS 16+, bundle id `com.philbert.richstalk`) that lists
billionaires with a short profile each, and shows the live positions of the
ones with publicly documented private jets on a MapKit map with a
standard/satellite toggle.

**Status: NOT compile-verified.** There is no Xcode or Swift toolchain on the
machine that built this project, so nothing here has ever been compiled, run,
or tested on a device. The Swift files pass a brace/paren balance check and
the dataset JSON validates, but that is not a build. Before anyone calls this
done, it needs: an Xcode build, a run on a real iPhone, a check that the
OpenSky states call returns live rows, and a check that the map pins appear.

## What is in the app

- **Billionaires tab** — a searchable system list. Each row shows name,
  source of wealth, country, and net worth. A filter switches between All,
  Tracked jets, and No tracked jet. Tapping a person opens their detail
  screen: rank, net worth, country, source, one-line bio, and their jet
  section.
- **Map tab** — a MapKit map with a Standard/Satellite segmented control, a
  Refresh button, and a status list underneath. Pins appear only for aircraft
  with a live, airborne OpenSky position. Aircraft with no live signal get no
  pin — the map never shows a guessed, stale, or replayed position as live.
- **Detail live status** — for a tracked jet: airborne callsign, altitude
  (feet), speed (knots), and the most recent flight's departure → arrival
  airport codes (last 24 hours, when OpenSky has one). Airport codes are
  shown as codes only; OpenSky does not supply airport names.
- **Design** — Apple Human Interface Guidelines throughout: system
  TabView/NavigationStack, `.searchable`, semantic colors, system text
  styles with Dynamic Type, no forced light/dark appearance, no custom
  chrome. No API keys or secrets anywhere in the code.

## Data sources

### Billionaire list — `RichStalk/Billionaires.json` (211 people)

- **Main tranche (206 people):** Forbes' 39th annual World's Billionaires
  List (2025). Forbes used stock prices and exchange rates from
  **March 7, 2025**; the list has 3,028 billionaires worth $16.1 trillion
  combined. This bundle holds ranks 1–199 including ties — 206 people.
  Figures, countries, industries, and the one-line descriptions are taken
  from that list's entries. The remaining ~2,822 people on the full 2025
  list are **not** in this bundle, and the app says so on its About screen
  rather than pretending the list is complete.
- **Extra tranche (5 people):** Forbes' 2025 celebrity-billionaire
  reporting, added because these five have publicly documented jets:
  Donald Trump (~$5.1B), Michael Jordan ($3.5B), Jay-Z ($2.5B),
  Kim Kardashian ($1.7B), Taylor Swift ($1.6B). These have no annual-list
  rank in the bundle (`rank: null`) and the detail screen says so.
- **Staleness is visible by design:** the snapshot date (March 7, 2025) is
  shown on the list header, on the About screen, and in the JSON header.
  Net worths are estimates that move daily with the markets; do not treat
  any figure here as current.

### Live positions — OpenSky Network (free, no key)

- `GET https://opensky-network.org/api/states/all?icao24=<hex,hex,…>` —
  one request for all tracked aircraft, returning callsign, latitude,
  longitude, barometric altitude, ground status, velocity, and track.
- `GET https://opensky-network.org/api/flights/aircraft?icao24=<hex>&begin=&end=`
  — most recent flight in the last 24 hours, for departure/arrival airport
  codes. Called only from a person's detail screen, to conserve quota.
- OpenSky's anonymous tier is rate-limited. The app therefore refreshes
  live states at most **once every 60 seconds**, only while the Map tab is
  open, and surfaces a 429 as a plain-language "rate limit reached" message
  instead of retrying in a loop.

### Aircraft registrations and ICAO24 codes — the part that must not be faked

A person is "tracked" only if at least one aircraft registration is publicly
documented for them. Each aircraft entry records `hexSource`:

- **"published"** — the ICAO24 code was independently published alongside
  the registration (Elon Musk's three jets, Zuckerberg's jet, Trump's 757).
- **"computed"** — the ICAO24 code was derived from the registration with
  the FAA's deterministic US N-number → Mode S allocation algorithm
  (offset `0xA00001`, bases 101711/10111, as published in the FlightAware
  forum's N-number converter). The implementation was validated against
  **5 independently published pairs** before any computed code was used:
  N628TS → a835af, N272BG → a2ae0a, N502SX → a64304,
  N68885 → a9247d, N757AF → aa3410 — all 5 reproduced exactly.
  Computed codes are still labeled "computed" in the app so a reader can
  tell them apart from published ones.

## Who has live tracking vs. profile-only

**Live tracking — 9 people, 14 aircraft:**

| Person | Aircraft (registration → ICAO24) |
|---|---|
| Elon Musk | N628TS → a835af (Gulfstream G650ER), N272BG → a2ae0a (Gulfstream G550), N502SX → a64304 (model not stated) |
| Mark Zuckerberg | N68885 → a9247d (Gulfstream G650ER) |
| Jeff Bezos | N11AF → a029e0 (Gulfstream G700), N756LB → aa314f (Gulfstream G650ER), N194PJ → a17855 (Pilatus PC-24) |
| Bill Gates | N887WM → ac39d6 (Gulfstream G650), N194WM → a17907 (Gulfstream G650) |
| Donald Trump | N757AF → aa3410 (Boeing 757-200) |
| Michael Jordan | N236MJ → a21fe6 (Gulfstream G550) |
| Jay-Z | N44440 → a55c76 (model not stated) |
| Kim Kardashian | N1980K → a18845 (Gulfstream G650ER) |
| Taylor Swift | N621MM → a81b13 (Dassault Falcon 7X) |

Notes on exclusions, so they are not mistaken for oversights:

- Bezos' G650ER **N271DV was listed for sale in late 2024** and is not
  tracked as an active fleet aircraft.
- Taylor Swift's older Falcon 900 **N898TS was sold** and is not tracked;
  only the current Falcon 7X (N621MM) is.
- People who charter, fly fractional (e.g. NetJets), or whose aircraft are
  held opaquely have no registration to track and show the honest
  "No publicly tracked jet" state. That state does **not** mean they never
  fly privately.

**Profile-only — the other 202 people.** Their detail screens show the
"No publicly tracked jet" card with the explanation above.

## Honest limitations (read before trusting the map)

1. **Privacy blocking is real.** Operators can enroll in the FAA's LADD
   (Limiting Aircraft Data Displayed) program or use PIA alternate ICAO
   codes that rotate. A jet using either will not appear under its
   documented code, or will appear only intermittently. A missing dot is
   not evidence the jet is not flying.
2. **Coverage gaps.** OpenSky depends on volunteer ADS-B receivers. Remote
   areas, oceans, and parts of the southern hemisphere have thin coverage;
   a jet can be airborne and invisible to OpenSky.
3. **A tracked jet is not proof its owner is on board.** Aircraft fly
   empty repositioning legs, maintenance flights, and with other
   passengers. The app tracks aircraft, not people.
4. **Anonymous OpenSky quota.** If the rate limit is hit, live updates
   pause and the app says so. A free OpenSky account (OAuth2 client
   credentials) would raise the quota; that is a future step, not
   something this build includes, and it would need credentials handled
   outside the code.
5. **Net worths are a snapshot.** See "Data sources" above. Nothing in
   the app refreshes net worths.
6. **Not compile-verified.** See the status note at the top. In
   particular, the hand-written `project.pbxproj` has not been opened by
   Xcode; if Xcode complains about it, regenerating the project in Xcode
   around the same source files is the fallback.

## Tracking data flow

```
Billionaires.json (bundle)
  → BillionaireStore.trackedAircraft() → 14 ICAO24 codes
  → TrackingStore (60-second loop, Map tab visible only)
  → OpenSkyService.fetchStates(icao24s:) — one request
  → states keyed by ICAO24 → map pins + detail live status
Detail screen only:
  → OpenSkyService.fetchMostRecentFlight(icao24:) — last 24h
  → departure → arrival airport codes
No position is ever stored, replayed, or synthesized.
```

## File layout

```
jet-tracker/
  README.md
  RichStalk.xcodeproj/project.pbxproj
  RichStalk/
    RichStalkApp.swift        — @main entry point
    Models.swift              — Billionaire / Aircraft / dataset loader
    OpenSkyService.swift      — OpenSky states + flights client, decoding
    TrackingStore.swift       — 60s refresh loop, published live state
    ContentView.swift         — TabView (Billionaires / Map)
    BillionaireListView.swift — searchable list + filter + About sheet
    BillionaireDetailView.swift — profile + jet live status / no-jet state
    TrackingMapView.swift     — MapKit wrapper, standard/satellite toggle
    Billionaires.json         — 211 entries (206 ranked + 5 extras)
    Info.plist                — display name RichStalk, iOS 16+
    Assets.xcassets/          — AppIcon set (needs real icon images added)
```

## Still needs a real-device / Xcode test

1. Open `RichStalk.xcodeproj` in Xcode; fix any project-file complaints.
2. Add real AppIcon images (the set currently has no image files).
3. Set a development team and build for a real iPhone (iOS 16+).
4. Confirm the list loads all 211 entries and search/filter work.
5. Confirm the Map tab fetches OpenSky states and pins appear for any
   airborne tracked jet; confirm the no-signal and rate-limit states.
6. Confirm the standard/satellite toggle switches the map type.
7. Confirm a detail screen shows origin → destination for a recently
   flown jet, and the no-tracked-jet card for a profile-only person.
8. Only after 1–7 pass should this be called working — and even then,
   only as "working on the day it was tested", since live data depends on
   OpenSky and on jets not being privacy-blocked.
