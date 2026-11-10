import SwiftUI

// MARK: - Saved locations
//
// The shift location picker is a list: places you've added yourself plus
// every location already on your shifts, each with when you last worked
// there. Picking one writes its name (and the pin from your latest shift
// there, if it had one) onto the shift.

/// One row in the picker.
struct ShiftLocationSummary: Identifiable, Hashable {
    var id: String { name.lowercased() }
    let name: String
    let lastWorked: Date?
    let shiftCount: Int
    let latitude: Double?
    let longitude: Double?

    var place: ShiftPlace { ShiftPlace(name: name, latitude: latitude, longitude: longitude) }

    var subtitle: String {
        guard let lastWorked else { return "Not worked here yet" }
        let cal = Calendar.current
        let when: String
        if cal.isDateInToday(lastWorked) {
            when = "today"
        } else if cal.isDateInYesterday(lastWorked) {
            when = "yesterday"
        } else if cal.isDate(lastWorked, equalTo: Date(), toGranularity: .year) {
            when = lastWorked.formatted(.dateTime.month(.abbreviated).day())
        } else {
            when = lastWorked.formatted(.dateTime.month(.abbreviated).day().year())
        }
        let shifts = shiftCount == 1 ? "1 shift" : "\(shiftCount) shifts"
        return "Last worked \(when) · \(shifts)"
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }
}

/// Locations added by hand, and ones removed from the list. Local to the
/// device and cleared with the rest of the account's local data.
enum SavedLocationsStore {
    private static let savedKey = "saved_locations_v1"
    private static let hiddenKey = "hidden_locations_v1"
    static let nameLimit = 120

    static var saved: [String] { UserDefaults.standard.stringArray(forKey: savedKey) ?? [] }
    private static var hidden: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
    }

    static func add(_ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        guard !clean.isEmpty else { return }
        var list = saved.filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        list.append(clean)
        UserDefaults.standard.set(list, forKey: savedKey)
        UserDefaults.standard.set(Array(hidden.subtracting([clean.lowercased()])), forKey: hiddenKey)
    }

    /// Takes it off the list. Shifts already logged there keep their location.
    static func remove(_ name: String) {
        UserDefaults.standard.set(saved.filter { $0.caseInsensitiveCompare(name) != .orderedSame },
                                  forKey: savedKey)
        UserDefaults.standard.set(Array(hidden.union([name.lowercased()])), forKey: hiddenKey)
    }

    static func isHidden(_ name: String) -> Bool { hidden.contains(name.lowercased()) }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: savedKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
}

extension HoursStore {
    /// Every location to offer: worked-at places newest first, then saved
    /// places not worked at yet.
    func shiftLocationSummaries() -> [ShiftLocationSummary] {
        struct Acc { var name: String; var last: Date; var count: Int; var lat: Double?; var lon: Double? }
        var byKey: [String: Acc] = [:]
        for entry in allEntriesIncludingArchive() where !entry.isOffDay {
            let name = entry.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if var acc = byKey[key] {
                acc.count += 1
                if entry.date > acc.last {
                    acc.last = entry.date
                    acc.name = name
                    if entry.latitude != nil { acc.lat = entry.latitude; acc.lon = entry.longitude }
                } else if acc.lat == nil, entry.latitude != nil {
                    acc.lat = entry.latitude; acc.lon = entry.longitude
                }
                byKey[key] = acc
            } else {
                byKey[key] = Acc(name: name, last: entry.date, count: 1,
                                 lat: entry.latitude, lon: entry.longitude)
            }
        }
        var result = byKey.values
            .filter { !SavedLocationsStore.isHidden($0.name) }
            .sorted { $0.last > $1.last }
            .map { ShiftLocationSummary(name: $0.name, lastWorked: $0.last, shiftCount: $0.count,
                                        latitude: $0.lat, longitude: $0.lon) }
        for name in SavedLocationsStore.saved where byKey[name.lowercased()] == nil {
            result.append(ShiftLocationSummary(name: name, lastWorked: nil, shiftCount: 0,
                                               latitude: nil, longitude: nil))
        }
        return result
    }
}

// MARK: - Picker sheet

struct SavedLocationPickerSheet: View {
    @Binding var place: ShiftPlace
    @State var locations: [ShiftLocationSummary]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isAdding = false
    @State private var newName = ""
    @State private var pendingDelete: ShiftLocationSummary?
    @FocusState private var nameFocused: Bool

    private var filtered: [ShiftLocationSummary] { locations.filter { $0.matches(query) } }
    private var recent: [ShiftLocationSummary] { Array(filtered.prefix(3)) }
    private var rest: [ShiftLocationSummary] { Array(filtered.dropFirst(3)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    if !locations.isEmpty { searchField }

                    if locations.isEmpty {
                        note(title: "No saved locations yet",
                             detail: "Add one below and it'll be here every time you log a shift.")
                    } else if filtered.isEmpty {
                        note(title: nil, detail: "No matches for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))” — add it below.")
                    } else {
                        if !recent.isEmpty { section("Recent", recent) }
                        if !rest.isEmpty { section("All Locations", rest) }
                    }

                    addSection
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !place.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") {
                            Haptics.lightTap()
                            place = ShiftPlace()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            if locations.isEmpty { isAdding = true; nameFocused = true }
        }
        .alert("Remove this location?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { location in
            Button("Remove", role: .destructive) {
                Haptics.mediumTap()
                SavedLocationsStore.remove(location.name)
                locations.removeAll { $0.id == location.id }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Shifts you've already logged there keep their location.")
        }
    }

    private var searchField: some View {
        AddShiftPanel(padding: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
                TextField("Search locations", text: $query)
                    .appText(.body)
                    .foregroundStyle(AppColors.text)
                    .tint(AppColors.accent)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(AppColors.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
        }
    }

    private func section(_ title: String, _ items: [ShiftLocationSummary]) -> some View {
        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel(title)
            AddShiftPanel {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, location in
                    if index > 0 { EntryRowDivider() }
                    row(location)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = location
                            } label: {
                                Label("Remove from list", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func row(_ location: ShiftLocationSummary) -> some View {
        let selected = place.trimmedName.caseInsensitiveCompare(location.name) == .orderedSame
        return Button {
            Haptics.lightTap()
            place = selected ? ShiftPlace() : location.place
            dismiss()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .fill(AppColors.accent.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "mappin.and.ellipse")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    Text(location.subtitle)
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                        .lineLimit(1)
                }
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppColors.accent : AppColors.faint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func note(title: String?, detail: String) -> some View {
        AddShiftPanel {
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .appText(.headline)
                        .foregroundStyle(AppColors.text)
                }
                Text(detail)
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addSection: some View {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: AppSpacing.xs) {
            AddShiftPanel {
                Button {
                    Haptics.lightTap()
                    withAnimation(AppMotion.Spring.smooth) { isAdding.toggle() }
                    if isAdding {
                        if newName.isEmpty { newName = query.trimmingCharacters(in: .whitespacesAndNewlines) }
                        nameFocused = true
                    }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                            .fill(AppColors.accent.opacity(0.14))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(AppColors.accent)
                            )
                        Text("Add New Location")
                            .appText(.headline)
                            .foregroundStyle(AppColors.accent)
                        Spacer(minLength: AppSpacing.xs)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.faint)
                            .rotationEffect(.degrees(isAdding ? 180 : 0))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isAdding {
                    EntryRowDivider()
                    TextField("Location name (e.g. Main Yard)", text: $newName)
                        .appText(.body)
                        .foregroundStyle(AppColors.text)
                        .tint(AppColors.accent)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .padding(.vertical, AppSpacing.sm)
                        .onChange(of: newName) { _, value in
                            if value.count > SavedLocationsStore.nameLimit {
                                newName = String(value.prefix(SavedLocationsStore.nameLimit))
                            }
                        }
                    Button("Save Location", action: save)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(trimmed.isEmpty)
                        .opacity(trimmed.isEmpty ? 0.55 : 1)
                }
            }

            Text("Location is optional — you can continue without picking one.")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AppSpacing.xxs)
        }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        SavedLocationsStore.add(name)
        Haptics.lightTap()
        // An existing place with the same name keeps its pin.
        place = locations.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.place
            ?? ShiftPlace(name: name)
        dismiss()
    }
}
