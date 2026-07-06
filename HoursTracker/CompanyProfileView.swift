import SwiftUI

struct CompanyProfileView: View {
    var store: HoursStore? = nil

    @AppStorage("company_name") private var companyName: String = ""
    @AppStorage("company_occupation") private var occupation: String = ""
    @AppStorage("company_employee_id") private var employeeID: String = ""
    @AppStorage("company_hourly_rate") private var hourlyRate: Double = 0
    @AppStorage("company_start_date_ts") private var companyStartDateTS: Double = 0

    @State private var startDate: Date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Company Details")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    field(title: "Company Name", text: $companyName, placeholder: "Your Company Name")

                    startDateField

                    if !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, companyStartDateTS > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.checkmark.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.accent)
                            Text("\(tenureString) at \(companyName.trimmingCharacters(in: .whitespacesAndNewlines))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.subtext)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.card2)
                                .overlay(Capsule().stroke(AppTheme.Colors.accent.opacity(0.3), lineWidth: 1))
                        )
                    }

                    field(title: "Occupation", text: $occupation, placeholder: "e.g. Asphalt / Concrete / Foreman")
                    field(title: "Employee ID (optional)", text: $employeeID, placeholder: "e.g. EMP-12345")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hourly Rate (optional)")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.subtext)

                        HStack {
                            Text("$")
                                .foregroundStyle(AppTheme.Colors.subtext)
                            TextField("0", value: $hourlyRate, format: .number)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(.white)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.Colors.card2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(16)
                .background(cardBackground)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .background(AppTheme.Colors.bg.ignoresSafeArea())
        .navigationTitle("Company Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if companyStartDateTS > 0 {
                startDate = Date(timeIntervalSince1970: companyStartDateTS)
            }
        }
        .onChange(of: startDate) { _, newDate in
            companyStartDateTS = newDate.timeIntervalSince1970
            rescheduleAnniversaryIfNeeded()
            store?.syncProfileSnapshotToCloud()
        }
        .onChange(of: companyName) { _, _ in
            rescheduleAnniversaryIfNeeded()
            store?.syncProfileSnapshotToCloud()
        }
        .onChange(of: occupation) { _, _ in
            store?.syncProfileSnapshotToCloud()
        }
        .onDisappear {
            store?.syncProfileSnapshotToCloud()
        }
    }

    private var startDateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start Date")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)

            HStack {
                DatePicker(
                    "Start date",
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(AppTheme.Colors.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.card2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                    )
            )

            Text("Used for work anniversaries and your Career company card.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.Colors.faint)
        }
    }

    private var tenureString: String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: startDate, to: Date())
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        if years == 0 && months == 0 { return "Less than a month" }
        if years == 0 { return "\(months) month\(months == 1 ? "" : "s")" }
        if months == 0 { return "\(years) year\(years == 1 ? "" : "s")" }
        return "\(years) yr \(months) mo"
    }

    private func rescheduleAnniversaryIfNeeded() {
        let name = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, companyStartDateTS > 0 else { return }
        let start = Date(timeIntervalSince1970: companyStartDateTS)
        Task {
            let granted = await NotificationManager.shared.hasPermission()
            if granted {
                SmartNotifier.shared.scheduleWorkAnniversaryNotification(
                    companyName: name,
                    startDate: start
                )
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(AppTheme.Colors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.Colors.stroke, lineWidth: 1)
            )
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.subtext)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.Colors.card2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.Colors.stroke, lineWidth: 1)
                        )
                )
        }
    }
}
