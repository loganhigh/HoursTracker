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

    @State private var query: String = ""
    @State private var isAddingNew: Bool = false
    @State private var draft = JobSiteDraft()
    @FocusState private var nameFocused: Bool

    private var ordered: [JobSite] { store.jobSitesByRecency }
    private var filtered: [JobSite] { ordered.filter { $0.matches(query) } }
    private var recent: [JobSite] { Array(filtered.prefix(3)) }
    private var rest: [JobSite] { Array(filtered.dropFirst(3)) }

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
                            if !rest.isEmpty {
                                section(title: "All Locations / Jobs", sites: rest)
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
            if ordered.isEmpty && selectedSiteID == nil { isAddingNew = true }
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
                    JobSiteFormFields(draft: $draft, nameFocused: $nameFocused)
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
    var iconName: String = JobSite.defaultIcon
    var createdAt: Date = Date()
    var lastUsedAt: Date?

    init() {}

    init(site: JobSite) {
        id = site.id
        name = site.name
        detail = site.detail
        iconName = site.iconName
        createdAt = site.createdAt
        lastUsedAt = site.lastUsedAt
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func makeSite() -> JobSite {
        JobSite(
            id: id ?? UUID().uuidString,
            name: name,
            detail: detail,
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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            nameField
            TextField("Address or detail (optional)", text: $draft.detail)
                .appText(.body)
                .foregroundStyle(AppColors.text)
                .tint(AppColors.accent)

            Text("Icon")
                .appText(.eyebrow)
                .foregroundStyle(AppColors.subtext)

            HStack(spacing: AppSpacing.xs) {
                ForEach(JobSite.iconOptions, id: \.self) { icon in
                    iconButton(icon)
                }
            }
        }
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

    private func iconButton(_ icon: String) -> some View {
        let isSelected = draft.iconName == icon
        return Button {
            Haptics.lightTap()
            draft.iconName = icon
        } label: {
            RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                .fill(AppColors.accent.opacity(isSelected ? 0.14 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                        .stroke(isSelected ? AppColors.accent.opacity(0.45) : AppColors.stroke, lineWidth: 1)
                )
                .frame(height: 36)
                .overlay(
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.subtext)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
