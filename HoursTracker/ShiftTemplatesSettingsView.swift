import SwiftUI

// MARK: - Shift Templates management (Settings · Hour Tracker Pro)
//
// Save the shifts you work over and over — "Morning Shift, 6:00 AM – 5:00 PM"
// — then fill the Add Shift wizard from one in a single tap. Deleting a
// template NEVER edits past shifts: a template only ever pre-fills the
// wizard, it is not stored on the entry.

struct ShiftTemplatesSettingsView: View {
    @ObservedObject var store: HoursStore
    @ObservedObject private var premium = PremiumManager.shared

    @State private var editingTemplate: ShiftTemplate?
    @State private var isAddingNew = false
    @State private var pendingDelete: ShiftTemplate?
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            Form {
                Section {
                    if store.shiftTemplates.isEmpty {
                        Text("No templates yet. Save the shift you work most and log it in one tap.")
                            .appText(.caption)
                            .foregroundStyle(AppColors.subtext)
                    }

                    ForEach(store.shiftTemplatesByRecency) { template in
                        Button {
                            guard requirePro() else { return }
                            editingTemplate = template
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                SettingsRowLabel(
                                    icon: "square.on.square",
                                    title: template.name,
                                    subtitle: template.displaySubtitle
                                )
                                Spacer(minLength: AppSpacing.xs)
                                Text(AppTheme.Format.hours(template.paidHours))
                                    .appText(.headline)
                                    .monospacedDigit()
                                    .foregroundStyle(AppColors.subtext)
                                SettingsChevron()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = template
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        guard requirePro() else { return }
                        isAddingNew = true
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            SettingsRowLabel(icon: "plus", title: "Add Template", titleTint: AppColors.accent)
                            Spacer(minLength: AppSpacing.xs)
                            if !premium.isPremium {
                                Image(systemName: "crown.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                } header: {
                    SectionEyebrow("Shift Templates")
                } footer: {
                    Text(premium.isPremium
                         ? "Saved on this device. Picking a template when you add a shift fills in its times, break, and location."
                         : "Shift Templates are part of Hour Tracker Pro.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Shift Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $editingTemplate) { template in
            ShiftTemplateEditorSheet(store: store, existing: template)
        }
        .sheet(isPresented: $isAddingNew) {
            ShiftTemplateEditorSheet(store: store, existing: nil)
        }
        .sheet(isPresented: $showingPaywall) {
            PremiumUpgradeView()
        }
        .alert("Delete this template?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    Haptics.mediumTap()
                    store.deleteShiftTemplate(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Shifts you've already logged are not affected.")
        }
    }

    /// Returns true when the action may proceed; otherwise opens the paywall.
    private func requirePro() -> Bool {
        guard premium.isPremium else {
            Haptics.lightTap()
            showingPaywall = true
            return false
        }
        return true
    }
}

// MARK: - Editor sheet (add / edit one template)

struct ShiftTemplateEditorSheet: View {
    @ObservedObject var store: HoursStore
    let existing: ShiftTemplate?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int
    @State private var showCustomBreak: Bool
    @State private var locationName: String
    @State private var showDeleteConfirm = false

    init(store: HoursStore, existing: ShiftTemplate?) {
        self.store = store
        self.existing = existing
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        // Direct assignment rather than `.map(...)` on the optional: passing a
        // main-actor-isolated initializer as a function value trips the
        // concurrency checker (same reason as JobSiteEditorSheet).
        if let existing {
            _name = State(initialValue: existing.name)
            _start = State(initialValue: existing.date(existing.startMinutes, on: day))
            _end = State(initialValue: existing.date(existing.endMinutes, on: day))
            _breakMinutes = State(initialValue: existing.breakMinutes)
            _showCustomBreak = State(initialValue: existing.breakMinutes > 0
                                     && ![15, 30, 45, 60].contains(existing.breakMinutes))
            _locationName = State(initialValue: existing.locationName)
        } else {
            _name = State(initialValue: "")
            _start = State(initialValue: cal.date(byAdding: .hour, value: 7, to: day) ?? day)
            _end = State(initialValue: cal.date(byAdding: .hour, value: 17, to: day) ?? day)
            _breakMinutes = State(initialValue: 0)
            _showCustomBreak = State(initialValue: false)
            _locationName = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        AddShiftPanel {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Template Name")
                                    .appText(.metricLabel)
                                    .foregroundStyle(AppColors.subtext)
                                TextField("e.g. Morning Shift", text: $name)
                                    .appText(.body)
                                    .foregroundStyle(AppColors.text)
                                    .tint(AppColors.accent)
                            }
                        }

                        AddShiftPanel {
                            timeRow(title: "Start Time", selection: $start)
                            EntryRowDivider()
                            timeRow(title: "End Time", selection: $end)
                        }

                        EntryBreakSection(breakMinutes: $breakMinutes, showCustom: $showCustomBreak)

                        AddShiftPanel {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Location / Job (optional)")
                                    .appText(.metricLabel)
                                    .foregroundStyle(AppColors.subtext)
                                TextField("e.g. Main Yard", text: $locationName)
                                    .appText(.body)
                                    .foregroundStyle(AppColors.text)
                                    .tint(AppColors.accent)
                            }
                        }

                        AddShiftTotalTimePanel(hours: previewHours, caption: previewCaption)

                        if existing != nil {
                            Button {
                                Haptics.lightTap()
                                showDeleteConfirm = true
                            } label: {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Delete Template")
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
            .navigationTitle(existing == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert("Delete this template?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let existing {
                        Haptics.mediumTap()
                        store.deleteShiftTemplate(existing)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Shifts you've already logged are not affected.")
            }
        }
    }

    private func timeRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .appText(.headline)
                .foregroundStyle(AppColors.text)
            Spacer(minLength: AppSpacing.xs)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(AppColors.accent)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Derived

    private var draft: ShiftTemplate {
        ShiftTemplate(
            id: existing?.id ?? UUID().uuidString,
            name: name,
            startMinutes: ShiftTemplate.minutes(from: start),
            endMinutes: ShiftTemplate.minutes(from: end),
            breakMinutes: breakMinutes,
            locationName: locationName,
            createdAt: existing?.createdAt ?? Date(),
            lastUsedAt: existing?.lastUsedAt
        )
    }

    private var previewHours: Double { draft.paidHours }

    private var previewCaption: String {
        let range = draft.timeRangeText
        return breakMinutes > 0 ? "\(range) · \(breakMinutes)m break" : range
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && previewHours > 0
    }

    private func save() {
        guard isValid else { return }
        Haptics.success()
        if existing == nil {
            store.addShiftTemplate(draft)
        } else {
            store.updateShiftTemplate(draft)
        }
        dismiss()
    }
}
