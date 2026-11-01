import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct OfficeSetupView: View {
    @Environment(OfficeMonitor.self) private var monitor
    @Query private var visits: [Visit]
    @State private var center: CLLocationCoordinate2D?
    @State private var radius: CLLocationDistance = 150
    @State private var customDelayMinutes: Int?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isLocating = false
    @State private var query = ""
    @State private var searchResults: [MKMapItem] = []

    private var draft: OfficeLocation? {
        center.map {
            OfficeLocation(latitude: $0.latitude, longitude: $0.longitude, radius: radius, timeInDelayMinutes: customDelayMinutes)
        }
    }

    var body: some View {
        let suggestion = OfficeSuggestion.detect(from: visits)
        let newSuggestion = suggestion.flatMap { suggestion -> OfficeSuggestion? in
            guard suggestion.isConfident else { return nil }
            guard let office = monitor.office else { return suggestion }
            let distance = CLLocation(latitude: office.latitude, longitude: office.longitude)
                .distance(from: CLLocation(latitude: suggestion.latitude, longitude: suggestion.longitude))
            return distance > office.radius ? suggestion : nil
        }

        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $camera) {
                        UserAnnotation()
                        if let newSuggestion {
                            Marker("Detected office", systemImage: "sparkles", coordinate: newSuggestion.coordinate)
                                .tint(.orange)
                        }
                        if let center {
                            MapCircle(center: center, radius: radius)
                                .foregroundStyle(.tint.opacity(0.2))
                                .stroke(.tint, lineWidth: 2)
                            Marker("Office", systemImage: "building.2.fill", coordinate: center)
                        }
                    }
                    .onMapCameraChange { visibleRegion = $0.region }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            center = coordinate
                        }
                    }
                }

                Form {
                    if let newSuggestion {
                        Section("Detected from your routine") {
                            Text("""
                                You've spent the workday here on \(newSuggestion.dayCount) days, usually arriving \
                                around \(newSuggestion.usualArrival.formatted(date: .omitted, time: .shortened)).
                                """)
                            Button("Use detected location", systemImage: "sparkles") {
                                focus(on: newSuggestion.coordinate)
                            }
                        }
                    } else if monitor.office == nil {
                        Section("Detected from your routine") {
                            Text("""
                                Learning your routine: \(suggestion?.dayCount ?? 0) of \(OfficeSuggestion.requiredDays) \
                                workdays seen. Clockwise will suggest your office once it has seen you spend \
                                \(OfficeSuggestion.requiredDays) workdays at the same place.
                                """)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        LabeledContent("Radius", value: "\(Int(radius)) m")
                        Slider(value: $radius, in: OfficeLocation.minimumRadius...500, step: 10)
                        if let office = monitor.office, office.radius < OfficeLocation.minimumRadius {
                            Label(
                                "Your saved radius (\(Int(office.radius)) m) is too small for iOS to detect reliably while the app is closed. Tap Save office to use \(Int(radius)) m.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    } footer: {
                        Text("Search, tap the map, or use your location to place the office pin. A bigger radius detects you earlier but is less precise.")
                    }
                    Section {
                        let defaultDelay = OfficeLocation.defaultTimeInDelayMinutes(radius: radius)
                        Stepper(
                            value: Binding(
                                get: { customDelayMinutes ?? defaultDelay },
                                set: { customDelayMinutes = $0 }
                            ),
                            in: 0...60
                        ) {
                            LabeledContent(
                                "Time in after entering",
                                value: "\(customDelayMinutes ?? defaultDelay) min\(customDelayMinutes == nil ? " (default)" : "")"
                            )
                        }
                        Button("Reset to default (\(defaultDelay) min)", systemImage: "arrow.counterclockwise") {
                            customDelayMinutes = nil
                        }
                        .disabled(customDelayMinutes == nil)
                    } footer: {
                        Text("Entering the radius isn't the same as reaching the time clock. Your time in is recorded this many minutes after you enter. The default grows with the radius (8 min for 100 m).")
                    }
                    Section {
                        Button(isLocating ? "Locating..." : "Use my current location", systemImage: "location.fill") {
                            Task { await useCurrentLocation() }
                        }
                        .disabled(isLocating)
                        Button(draft != nil && draft == monitor.office ? "Saved" : "Save office", systemImage: "checkmark") {
                            if let draft {
                                monitor.setOffice(draft)
                            }
                        }
                        .disabled(draft == nil || draft == monitor.office)
                    }
                }
                .frame(height: 360)
            }
            .navigationTitle("Office")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search office name or address")
            .searchSuggestions {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        focus(on: item.placemark.coordinate)
                        query = ""
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Unnamed place")
                            if let address = item.placemark.title {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .task(id: query) {
                guard !query.isEmpty else {
                    searchResults = []
                    return
                }
                // Debounce: a new keystroke cancels this task before the search starts.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                if let visibleRegion {
                    request.region = visibleRegion
                }
                searchResults = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
            }
            .onAppear {
                guard center == nil, let office = monitor.office else { return }
                radius = max(office.radius, OfficeLocation.minimumRadius)
                customDelayMinutes = office.timeInDelayMinutes
                focus(on: office.coordinate)
            }
        }
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        center = coordinate
        camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))
    }

    private func useCurrentLocation() async {
        monitor.requestAuthorization()
        guard monitor.authorization != .denied, monitor.authorization != .restricted else { return }
        isLocating = true
        defer { isLocating = false }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                focus(on: location.coordinate)
                break
            }
        } catch {}
    }
}
