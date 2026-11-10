import SwiftUI
import CoreLocation
import UIKit

// MARK: - Settings → Arrive at work

/// Turns arrival prompts on, explains the location permission, and manages
/// the places that trigger them.
struct ArrivalAlertsView: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var monitor = ArrivalMonitor.shared
    @State private var editing: ArrivalSite?
    @State private var addingNew = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { monitor.isEnabled }, set: { monitor.setEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arrive at work prompts")
                            .appText(.headline)
                            .foregroundStyle(AppColors.text)
                        Text("A notification to start your live shift when you get to work, and to clock out when you leave.")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }
                }
                .tint(AppColors.accent)

                if monitor.isEnabled && !monitor.hasAlwaysPermission {
                    permissionRow
                }
            } footer: {
                Text("Hour Tracker doesn't track where you go. iOS only lets it know when you arrive at or leave one of the places below.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
            }
            .listRowBackground(AppColors.card.opacity(0.55))

            Section {
                ForEach(monitor.sites) { site in
                    Button {
                        editing = site
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(site.enabled ? AppColors.accent : AppColors.faint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.name)
                                    .appText(.headline)
                                    .foregroundStyle(AppColors.text)
                                Text("Within \(Int(site.radius)) m\(site.enabled ? "" : " · Off")")
                                    .appText(.caption)
                                    .foregroundStyle(AppColors.subtext)
                            }
                            Spacer(minLength: 0)
                            SettingsChevron()
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { monitor.remove(site) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                if monitor.sites.count < ArrivalMonitor.maxSites {
                    Button {
                        Haptics.lightTap()
                        addingNew = true
                    } label: {
                        Label("Add work location", systemImage: "plus.circle.fill")
                            .foregroundStyle(AppColors.accent)
                    }
                }
            } header: {
                SectionEyebrow("Work locations")
            } footer: {
                if monitor.sites.isEmpty {
                    Text("Add the places you work. Drop the pin on the site itself, not the road out front.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
            }
            .listRowBackground(AppColors.card.opacity(0.55))
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.bg.ignoresSafeArea())
        .navigationTitle("Arrive at Work")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { site in
            ArrivalSiteEditor(store: store, site: site)
        }
        .sheet(isPresented: $addingNew) {
            ArrivalSiteEditor(store: store, site: nil)
        }
    }

    private var permissionRow: some View {
        let denied = monitor.authorization == .denied || monitor.authorization == .restricted
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("Location needs to be set to Always", systemImage: "exclamationmark.triangle.fill")
                .appText(.subheadline)
                .foregroundStyle(AppColors.warning)
            Text(denied
                 ? "Location is off for Hour Tracker. Turn it on in Settings → Hour Tracker → Location → Always."
                 : "iOS only tells the app you've arrived when location is allowed Always. It's still only used for the places you add.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
            Button(denied || monitor.authorization == .authorizedWhenInUse ? "Open Settings" : "Allow location") {
                if denied || monitor.authorization == .authorizedWhenInUse,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                } else {
                    monitor.requestAlwaysPermission()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / edit one place

private struct ArrivalSiteEditor: View {
    @ObservedObject var store: HoursStore
    let existing: ArrivalSite?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var place: ShiftPlace
    @State private var radius: Double
    @State private var enabled: Bool
    @State private var showingMap = false

    init(store: HoursStore, site: ArrivalSite?) {
        self.store = store
        existing = site
        _name = State(initialValue: site?.name ?? "")
        _place = State(initialValue: site?.place ?? ShiftPlace())
        _radius = State(initialValue: site?.radius ?? 150)
        _enabled = State(initialValue: site?.enabled ?? true)
    }

    /// Past shift locations that already have a pin: one tap to reuse.
    private var pinnedLocations: [ShiftLocationSummary] {
        store.shiftLocationSummaries().filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && place.coordinate != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Main Yard)", text: $name)
                        .onChange(of: name) { _, value in
                            if value.count > SavedLocationsStore.nameLimit {
                                name = String(value.prefix(SavedLocationsStore.nameLimit))
                            }
                        }
                } header: {
                    Text("Name")
                }

                Section {
                    Button {
                        showingMap = true
                    } label: {
                        HStack {
                            Label(place.coordinate == nil ? "Set the spot on a map" : "Move the pin",
                                  systemImage: "map")
                            Spacer()
                            if let c = place.coordinate {
                                Text(String(format: "%.4f, %.4f", c.latitude, c.longitude))
                                    .appText(.caption)
                                    .foregroundStyle(AppColors.subtext)
                            }
                        }
                    }
                    if !pinnedLocations.isEmpty {
                        ForEach(pinnedLocations.prefix(5)) { location in
                            Button {
                                place = location.place
                                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = location.name }
                            } label: {
                                Label("Use \(location.name)", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                } header: {
                    Text("Where")
                } footer: {
                    Text("Tip: standing at the site? Open the map and tap the location button.")
                }

                Section {
                    Picker("Notify within", selection: $radius) {
                        ForEach(ArrivalSite.radiusOptions, id: \.self) { r in
                            Text("\(Int(r)) m").tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Distance")
                } footer: {
                    Text("Bigger sites (yards, plants) work better with a larger distance.")
                }

                if existing != nil {
                    Section {
                        Toggle("Prompts for this place", isOn: $enabled)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Work Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let c = place.coordinate else { return }
                        var site = existing ?? ArrivalSite(name: name, latitude: c.latitude, longitude: c.longitude)
                        site.name = name
                        site.latitude = c.latitude
                        site.longitude = c.longitude
                        site.radius = radius
                        site.enabled = enabled
                        ArrivalMonitor.shared.save(site)
                        if !ArrivalMonitor.shared.isEnabled { ArrivalMonitor.shared.setEnabled(true) }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingMap, onDismiss: {
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = place.trimmedName }
            }) {
                ShiftLocationPickerSheet(place: $place, recentPlaces: store.recentShiftPlaces())
            }
        }
    }
}
