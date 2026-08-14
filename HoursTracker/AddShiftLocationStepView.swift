import SwiftUI

// MARK: - Add Shift · Location / Job picker sheet
//
// Presented from screen 1's "Location / Job" row (not a wizard step).
// Backed by real saved job sites (`JobSite`, persisted by `HoursStore`).
// Selecting a site writes its NAME into the shift's `locationName` — the
// entry model is unchanged and stores no site id, so renaming or deleting a
// site never rewrites shift history.
//
// Location stays optional: the user can dismiss with nothing selected.
// Picking a site (or saving a new one) fills the row and dismisses back to
// screen 1 automatically.

struct AddShiftLocationPickerSheet: View {
    @ObservedObject var store: HoursStore
    /// The chosen site's id, or nil when no site is selected.
    @Binding var selectedSiteID: String?
    /// The label that will be written to `WorkEntry.locationName`.
    @Binding var locationLabel: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var premium = PremiumManager.shared

    @State private var query: String = ""
    @State private var isAddingNew: Bool = false
    @State private var draft = JobSiteDraft()
    @State private var showingPaywall = false
    @FocusState private var nameFocused: Bool

    private var canAddMore: Bool { store.canAddJobSite(isPro: premium.isPremium) }

    private var ordered: [JobSite] { store.jobSitesByRecency }
    private var filtered: [JobSite] { ordered.filter { $0.matches(query) } }
    private var recent: [JobSite] { Array(filtered.prefix(3)) }
    private var rest: [JobSite] { Array(filtered.dropFirst(3)) }
    /// Everything past Recent, grouped by city. Recent stays ungrouped — it
    /// is a shortcut, and splitting three rows across city headings would
    /// bury the thing it exists to surface.
    private var restByCity: [(title: String, sites: [JobSite])] {
        store.jobSitesGroupedByCity(rest)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        if !ordered.isEmpty {
                            searchField
                        }

                        if ordered.isEmpty {
                            emptyStateNote
                        } else if filtered.isEmpty {
                            noMatchesNote
                        } else {
                            if !recent.isEmpty {
                                section(title: "Recent", sites: recent)
                            }
                            ForEach(restByCity, id: \.title) { group in
                                section(title: group.title, sites: group.sites)
                            }
                        }

                        addNewSection
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Location / Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if ordered.isEmpty && selectedSiteID == nil && canAddMore { isAddingNew = true }
        }
        .sheet(isPresented: $showingPaywall) {
            PremiumUpgradeView()
        }
    }

    // MARK: - Search

    private var searchField: some View {
        AddShiftPanel(padding: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.faint)
                TextField("Search locations or jobs", text: $query)
                    .appText(.body)
                    .foregroundStyle(AppColors.text)
                    .tint(AppColors.accent)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        Haptics.lightTap()
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

    // MARK: - Sections

    private func section(title: String, sites: [JobSite]) -> some View {
        VStack(spacing: AppSpacing.xs) {
            EntrySectionLabel(title)
            AddShiftPanel {
                ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                    if index > 0 { EntryRowDivider() }
                    AddShiftLocationRow(
                        icon: site.iconName,
                        name: site.name,
                        subtitle: site.displaySubtitle,
                        isSelected: selectedSiteID == site.id
                    ) {
                        toggle(site)
                    }
                }
            }
        }
    }

    private var emptyStateNote: some View {
        AddShiftPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text("No saved locations or jobs yet")
                    .appText(.headline)
                    .foregroundStyle(AppColors.text)
                Text("Add one below and it'll be here every time you log a shift.")
                    .appText(.caption)
                    .foregroundStyle(AppColors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noMatchesNote: some View {
        AddShiftPanel {
            Text("No matches for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))” — add it below.")
                .appText(.caption)
                .foregroundStyle(AppColors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Add new

    private var addNewSection: some View {
        VStack(spacing: AppSpacing.xs) {
            AddShiftPanel {
                Button {
                    Haptics.lightTap()
                    guard canAddMore else {
                        showingPaywall = true
                        return
                    }
                    withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
                        isAddingNew.toggle()
                    }
                    if isAddingNew {
                        if draft.name.isEmpty {
                            draft.name = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
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
                        Text("Add New Location / Job")
                            .appText(.headline)
                            .foregroundStyle(AppColors.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: AppSpacing.xs)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.faint)
                            .rotationEffect(.degrees(isAddingNew ? 180 : 0))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isAddingNew {
                    EntryRowDivider()
                    JobSiteFormFields(
                        draft: $draft,
                        nameFocused: $nameFocused,
                        knownCities: store.knownJobSiteCities
                    )
                        .padding(.top, AppSpacing.sm)
                    Button("Save Location / Job", action: commitDraft)
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!draft.isValid)
                        .opacity(draft.isValid ? 1 : 0.55)
                        .padding(.top, AppSpacing.sm)
                }
            }

            Text("Location and job are optional — you can continue without picking one.")
                .appText(.caption)
                .foregroundStyle(AppColors.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AppSpacing.xxs)
        }
    }

    // MARK: - Actions

    private func commitDraft() {
        guard draft.isValid else { return }
        let created = store.addJobSite(draft.makeSite())
        draft = JobSiteDraft()
        nameFocused = false
        query = ""
        withAnimation(AppMotion.animation(AppMotion.Spring.smooth, reduceMotion: reduceMotion)) {
            isAddingNew = false
        }
        apply(created)
    }

    private func toggle(_ site: JobSite) {
        if selectedSiteID == site.id {
            Haptics.lightTap()
            withAnimation(AppMotion.animation(AppMotion.Spring.snappy, reduceMotion: reduceMotion)) {
                selectedSiteID = nil
                locationLabel = ""
            }
        } else {
            apply(site)
        }
    }

    private func apply(_ site: JobSite) {
        Haptics.lightTap()
        store.markJobSiteUsed(id: site.id)
        selectedSiteID = site.id
        locationLabel = site.name
        dismiss()
    }
}

// MARK: - Shared draft + form fields (wizard "add new" and Settings management)

struct JobSiteDraft {
    var id: String?
    var name: String = ""
    var detail: String = ""
    var city: String = ""
    var iconName: String = JobSite.defaultIcon
    var createdAt: Date = Date()
    var lastUsedAt: Date?

    init() {}

    init(site: JobSite) {
        id = site.id
        name = site.name
        detail = site.detail
        city = site.city
        iconName = site.iconName
        createdAt = site.createdAt
        lastUsedAt = site.lastUsedAt
    }

    /// Name and city are both required. Existing sites saved before city
    /// existed keep working — this only gates the editor.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func makeSite() -> JobSite {
        JobSite(
            id: id ?? UUID().uuidString,
            name: name,
            detail: detail,
            city: city,
            iconName: iconName,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )
    }
}

/// Name + detail fields and the icon picker — shared by the wizard's inline
/// "add new" form and the Settings editor.
struct JobSiteFormFields: View {
    @Binding var draft: JobSiteDraft
    var nameFocused: FocusState<Bool>.Binding?
    /// Cities already in use, offered as chips. Tapping one reuses its exact
    /// spelling, which is what keeps a city from splitting into near-identical
    /// groups.
    var knownCities: [String] = []

    var body: some View {
        // Name and city only. Detail and icon still exist on the model, so
        // sites saved with them keep them — they are simply not asked for.
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            nameField

            TextField("City", text: $draft.city)
                .appText(.body)
                .foregroundStyle(AppColors.text)
                .tint(AppColors.accent)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !suggestedCities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(suggestedCities, id: \.self) { city in
                            cityChip(city)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    /// Chips for cities the user hasn't already typed.
    private var suggestedCities: [String] {
        let current = draft.city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return knownCities.filter { $0.lowercased() != current }
    }

    private func cityChip(_ city: String) -> some View {
        Button {
            Haptics.lightTap()
            draft.city = city
        } label: {
            Text(city)
                .appText(.caption)
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColors.accent.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nameField: some View {
        if let nameFocused {
            TextField("Location or job name", text: $draft.name)
                .appText(.body)
                .foregroundStyle(AppColors.text)
                .tint(AppColors.accent)
                .focused(nameFocused)
                .submitLabel(.done)
        } else {
            TextField("Location or job name", text: $draft.name)
                .appText(.body)
                .foregroundStyle(AppColors.text)
                .tint(AppColors.accent)
                .submitLabel(.done)
        }
    }

}
