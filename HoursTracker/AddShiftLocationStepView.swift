import SwiftUI

// MARK: - Job site form pieces
//
// Used by Settings → Job Sites. Shifts now take a map pin instead
// (ShiftLocationPicker.swift).

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
