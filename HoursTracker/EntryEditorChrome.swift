import SwiftUI

// MARK: - Entry editor chrome
//
// The editor's header and pinned footer, split out of EntryEditorView to keep
// it under the 500-line limit. Edit mode reads distinct from add: an
// "Editing" eyebrow over the title.

struct EntryEditorHeader: View {
    let isEditing: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    Text("Editing")
                        .appText(.eyebrow)
                        .foregroundStyle(AppColors.accent)
                }
                Text(isEditing ? "Edit Shift" : "Add Shift")
                    .appText(.title)
                    .foregroundStyle(AppColors.text)
            }
            Spacer()
            Button("Cancel") {
                Haptics.lightTap()
                onCancel()
            }
            .appText(.subheadline)
            .foregroundStyle(AppColors.subtext)
            .padding(.vertical, AppSpacing.xxs)
        }
    }
}

struct EntryEditorFooter: View {
    let isEditing: Bool
    let canSave: Bool
    let isSaving: Bool
    let validationMessage: String
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            EntryValidationLine(isValid: canSave, message: validationMessage)
            Button(isEditing ? "Save Changes" : "Save Shift", action: onSave)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave || isSaving)
                .opacity(canSave ? 1 : 0.55)
        }
    }
}
