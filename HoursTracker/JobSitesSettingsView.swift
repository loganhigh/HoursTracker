import SwiftUI

// MARK: - Job Sites management (Settings)
//
// Rename, re-detail, re-icon, or delete the saved locations / jobs offered by
// the Add Shift wizard. Deleting a site NEVER edits past shifts — entries hold
// the location name as plain text, so history keeps whatever it was saved with.

struct JobSitesSettingsView: View {
    @ObservedObject var store: HoursStore

    @State private var editingSite: JobSite?
    @State private var isAddingNew = false
    @State private var pendingDelete: JobSite?

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            Form {
                Section {
                    if store.jobSites.isEmpty {
                        Text("No saved locations or jobs yet.")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }

                    ForEach(store.jobSitesByRecency) { site in
                        Button {
                            editingSite = site
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                SettingsRowLabel(
                                    icon: site.iconName,
                                    title: site.name,
                                    subtitle: site.displaySubtitle
                                )
                                Spacer(minLength: AppSpacing.xs)
                                SettingsChevron()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = site
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        isAddingNew = true
                    } label: {
                        SettingsRowLabel(icon: "plus", title: "Add Location / Job", titleTint: AppColors.accent)
                    }
                } header: {
                    SectionEyebrow("Job Sites")
                } footer: {
                    Text("Saved on this device. Picking one when you add a shift fills in its name — deleting a site never changes shifts you've already logged.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Job Sites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $editingSite) { site in
            JobSiteEditorSheet(store: store, existing: site)
        }
        .sheet(isPresented: $isAddingNew) {
            JobSiteEditorSheet(store: store, existing: nil)
        }
        .alert("Delete this location?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    Haptics.mediumTap()
                    store.deleteJobSite(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Shifts you've already logged keep their location name.")
        }
    }
}

// MARK: - Editor sheet (add / edit one site)

struct JobSiteEditorSheet: View {
    @ObservedObject var store: HoursStore
    let existing: JobSite?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: JobSiteDraft
    @State private var showDeleteConfirm = false

    init(store: HoursStore, existing: JobSite?) {
        self.store = store
        self.existing = existing
        // Direct call rather than `.map(JobSiteDraft.init)`: passing the
        // main-actor-isolated initializer as a function value into `map`
        // evaluates it in a nonisolated context and trips the concurrency
        // checker.
        if let existing {
            _draft = State(initialValue: JobSiteDraft(site: existing))
        } else {
            _draft = State(initialValue: JobSiteDraft())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        AddShiftPanel {
                            JobSiteFormFields(draft: $draft, nameFocused: nil)
                        }

                        if existing != nil {
                            Button {
                                Haptics.lightTap()
                                showDeleteConfirm = true
                            } label: {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Delete Location / Job")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.negative)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .fill(AppColors.negative.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                                .stroke(AppColors.negative.opacity(0.25), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(existing == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.isValid)
                }
            }
            .alert("Delete this location?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let existing {
                        Haptics.mediumTap()
                        store.deleteJobSite(existing)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Shifts you've already logged keep their location name.")
            }
        }
    }

    private func save() {
        guard draft.isValid else { return }
        Haptics.success()
        if existing == nil {
            store.addJobSite(draft.makeSite())
        } else {
            store.updateJobSite(draft.makeSite())
        }
        dismiss()
    }
}
