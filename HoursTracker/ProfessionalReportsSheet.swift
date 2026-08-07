import SwiftUI

/// Hour Tracker Pro — branded PDF exports (weekly/monthly), presented from
/// Settings → "Professional Reports". Sits alongside the free "Download My
/// Data" path (`DataExportSheet`) without touching it. Reuses `ShareSheet`
/// and `SettingsExportShareItem` from SettingsSheets.swift.
struct ProfessionalReportsSheet: View {
    @ObservedObject var store: HoursStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("company_name") private var companyName: String = ""
    @ObservedObject private var logoManager = CompanyLogoManager.shared

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var shareItem: SettingsExportShareItem?

    private let exportService = ReportExportService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    reportButton(
                        title: "This Week",
                        subtitle: "Branded PDF for the current pay week",
                        icon: "calendar.day.timeline.left"
                    ) {
                        exportWeek()
                    }

                    reportButton(
                        title: "This Month",
                        subtitle: "Branded PDF summary and entry breakdown",
                        icon: "calendar"
                    ) {
                        exportMonth()
                    }
                } header: {
                    SectionEyebrow("Professional Reports")
                } footer: {
                    Text("PDF reports with your company name and logo, ready to share with clients or for your records. Add a name and logo in Company Profile.")
                        .appText(.caption)
                        .foregroundStyle(AppColors.subtext)
                }
                .listRowBackground(AppColors.card.opacity(0.55))
                .listRowSeparatorTint(AppColors.stroke)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.bg.ignoresSafeArea())
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url]) { shareItem = nil }
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "Export failed. Please try again.")
            }
        }
    }

    @ViewBuilder
    private func reportButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                SettingsRowLabel(
                    icon: icon,
                    title: isExporting ? "Preparing report..." : title,
                    subtitle: subtitle,
                    isBusy: isExporting
                )
                Spacer(minLength: AppSpacing.xs)
                SettingsChevron()
            }
        }
        .disabled(isExporting)
    }

    // MARK: - Actions

    private func exportWeek() {
        isExporting = true
        Task {
            do {
                let entries = store.allEntriesIncludingArchive()
                let url = try await exportService.exportPDF(
                    weekOf: Date(),
                    entries: entries,
                    store: store,
                    companyName: companyName,
                    logoImage: logoManager.localImage
                )
                isExporting = false
                shareItem = SettingsExportShareItem(url: url)
            } catch {
                isExporting = false
                exportError = (error as? LocalizedError)?.errorDescription ?? "Export failed. Please try again."
            }
        }
    }

    private func exportMonth() {
        isExporting = true
        Task {
            do {
                let entries = store.allEntriesIncludingArchive()
                let url = try await exportService.exportPDF(
                    monthDate: Date(),
                    entries: entries,
                    store: store,
                    companyName: companyName,
                    logoImage: logoManager.localImage
                )
                isExporting = false
                shareItem = SettingsExportShareItem(url: url)
            } catch {
                isExporting = false
                exportError = (error as? LocalizedError)?.errorDescription ?? "Export failed. Please try again."
            }
        }
    }
}
