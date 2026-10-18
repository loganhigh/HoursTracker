import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Shift location (map pin)
//
// A shift's work location is a pin on Apple Maps plus an optional name
// ("Main Yard"), stored on WorkEntry.latitude / longitude / locationName.
// There is no saved-locations list to manage: the picker offers the spots
// from your own recent shifts instead.

struct ShiftPlace: Equatable, Hashable {
    var name: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { trimmedName.isEmpty && coordinate == nil }

    init(name: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    init(entry: WorkEntry) {
        self.init(name: entry.locationName, latitude: entry.latitude, longitude: entry.longitude)
    }

    /// Writes the place onto an entry (clearing it when empty).
    func apply(to entry: inout WorkEntry) {
        entry.locationName = trimmedName
        entry.locationURL = ""
        entry.latitude = coordinate == nil ? nil : latitude
        entry.longitude = coordinate == nil ? nil : longitude
    }

    /// Label for rows: the name, else a short coordinate.
    var displayText: String? {
        if !trimmedName.isEmpty { return trimmedName }
        guard let latitude, let longitude else { return nil }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }
}

extension HoursStore {
    /// Distinct pinned places from recent shifts, newest first. Places within
    /// ~150 m of one already listed count as the same spot.
    func recentShiftPlaces(limit: Int = 6) -> [ShiftPlace] {
        var result: [ShiftPlace] = []
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            guard let lat = entry.latitude, let lon = entry.longitude else { continue }
            let here = CLLocation(latitude: lat, longitude: lon)
            let duplicate = result.contains {
                CLLocation(latitude: $0.latitude ?? 0, longitude: $0.longitude ?? 0).distance(from: here) < 150
            }
            if !duplicate { result.append(ShiftPlace(entry: entry)) }
            if result.count == limit { break }
        }
        return result
    }
}

// MARK: - Picker sheet

struct ShiftLocationPickerSheet: View {
    @Binding var place: ShiftPlace
    let recentPlaces: [ShiftPlace]
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isDragging = false
    @State private var name = ""
    /// The last name filled in automatically (search result / recent spot),
    /// so a later pick can replace it without overwriting a typed name.
    @State private var autoName = ""
    @State private var address = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var geocodeTask: Task<Void, Never>?
    @StateObject private var locator = PinLocator()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $camera) {
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onMapCameraChange(frequency: .continuous) { _ in
                    if !isDragging { isDragging = true }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    isDragging = false
                    center = context.region.center
                    visibleRegion = context.region
                    lookUpAddress(context.region.center)
                }
                .overlay { centerPin.allowsHitTesting(false) }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: AppSpacing.xs) {
                    searchField
                    if searchFocused, !results.isEmpty { resultsList }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
            }
            .safeAreaInset(edge: .bottom) { bottomCard }
            .navigationTitle("Where did you work?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: setUp)
        }
    }

    // MARK: Pin

    private var centerPin: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 40, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, AppColors.accent)
                .background(Circle().fill(.white).padding(6))
            Rectangle()
                .fill(AppColors.accent)
                .frame(width: 3, height: 14)
            Ellipse()
                .fill(.black.opacity(0.28))
                .frame(width: isDragging ? 18 : 10, height: 5)
        }
        // The tip of the stem sits on the map centre; lifts while dragging.
        .offset(y: isDragging ? -36 : -28)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .accessibilityHidden(true)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColors.subtext)
            TextField("Search an address or place", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit(search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.subtext)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.prefix(6).enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                Button {
                    select(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unnamed place")
                            .appText(.body)
                            .foregroundStyle(AppColors.text)
                        if let line = Self.addressLine(item.placemark) {
                            Text(line).appText(.caption).foregroundStyle(AppColors.subtext)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let visibleRegion { request.region = visibleRegion }
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            results = response?.mapItems ?? []
        }
    }

    private func select(_ item: MKMapItem) {
        Haptics.lightTap()
        searchFocused = false
        results = []
        if let itemName = item.name { suggestName(itemName) }
        move(to: item.placemark.coordinate)
    }

    // MARK: Bottom card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !recentPlaces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(recentPlaces, id: \.self) { recent in
                            Button {
                                Haptics.lightTap()
                                suggestName(recent.trimmedName)
                                if let c = recent.coordinate { move(to: c) }
                            } label: {
                                Label(recent.displayText ?? "Recent", systemImage: "clock.arrow.circlepath")
                                    .font(.system(.footnote, weight: .semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(AppColors.accent.opacity(0.16)))
                                    .foregroundStyle(AppColors.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(AppColors.accent)
                Text(isDragging ? "Moving pin…" : (address.isEmpty ? "Drag the map to place the pin" : address))
                    .appText(.subheadline)
                    .foregroundStyle(AppColors.subtext)
                    .lineLimit(2)
            }

            TextField("Name this place (optional), e.g. Main Yard", text: $name)
                .appText(.body)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.card2))

            Button {
                Haptics.lightTap()
                guard let center else { return }
                place = ShiftPlace(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                   latitude: center.latitude, longitude: center.longitude)
                dismiss()
            } label: {
                Text("Use this location")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(center == nil || isDragging)

            if !place.isEmpty {
                Button("Remove location", role: .destructive) {
                    Haptics.lightTap()
                    place = ShiftPlace()
                    dismiss()
                }
                .font(.system(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(AppSpacing.md)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(AppColors.surface)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: Behaviour

    private func setUp() {
        name = place.trimmedName
        if let c = place.coordinate ?? recentPlaces.first?.coordinate ?? WeatherService.shared.snapshot.map({
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }) {
            move(to: c, animated: false)
        } else {
            camera = .userLocation(fallback: .automatic)
            locator.requestIfNeeded()
        }
    }

    private func suggestName(_ suggestion: String) {
        guard name.trimmingCharacters(in: .whitespaces).isEmpty || name == autoName else { return }
        name = suggestion
        autoName = suggestion
    }

    private func move(to coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
        center = coordinate
        lookUpAddress(coordinate)
    }

    private func lookUpAddress(_ coordinate: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard !Task.isCancelled, let mark = placemarks?.first else { return }
            address = Self.addressLine(mark) ?? mark.name ?? ""
        }
    }

    static func addressLine(_ mark: CLPlacemark) -> String? {
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? mark.name : street, mark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Asks for when-in-use location the first time the picker has nowhere else
/// to start, so the map can open on where you are.
@MainActor
final class PinLocator: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

// MARK: - Row + preview

/// The editor's location row: a small non-interactive map of the pin with the
/// place name, or a prompt to drop one.
struct ShiftLocationRow: View {
    @Binding var place: ShiftPlace
    let recentPlaces: [ShiftPlace]
    @State private var showingPicker = false

    var body: some View {
        Button {
            Haptics.lightTap()
            showingPicker = true
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if let coordinate = place.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)),
                        interactionModes: []) {
                        Marker(place.trimmedName.isEmpty ? "Work" : place.trimmedName, coordinate: coordinate)
                            .tint(AppColors.accent)
                    }
                    .id(coordinate.latitude + coordinate.longitude)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                }
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(AppColors.accent)
                    Text(place.displayText ?? "Drop a pin for where you worked")
                        .appText(.body)
                        .foregroundStyle(place.isEmpty ? AppColors.subtext : AppColors.text)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.faint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPicker) {
            ShiftLocationPickerSheet(place: $place, recentPlaces: recentPlaces)
        }
    }
}
