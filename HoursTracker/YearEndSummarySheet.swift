import PDFKit
import SwiftUI

/// Pick a calendar year, preview its year-end summary PDF
/// and share it. Presented from Settings → Data & Backup.
struct YearEndSummarySheet: View {
    @ObservedObject var store: HoursStore

    @Environment(\.dismiss) private var dismiss
    @AppStorage("company_name") private var companyName: String = ""
    @ObservedObject private var logoManager = CompanyLogoManager.shared
    @ObservedObject private var friendsService = FriendsService.shared

    @State private var year: Int?
    @State private var pdfURL: URL?
    @State private var failed = false
    @State private var shareItem: SettingsExportShareItem?

    private var years: [Int] {
        let available = YearEndSummary.availableYears(store: store)
        return available.isEmpty ? [YearEndSummary.defaultYear(available: [])] : available
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                if let pdfURL {
                    YearEndPDFPreview(url: pdfURL)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
                        .padding(AppSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .fill(AppColors.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                        .stroke(AppColors.stroke, lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.xs)
                        .padding(.bottom, 96)
                } else if failed {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        owl: .oops,
                        title: "Couldn't create the PDF",
                        subtitle: "Please try again."
                    )
                } else {
                    VStack(spacing: AppSpacing.md) {
                        LoadingDots()
                        Text("Adding up your year…")
                            .appText(.subheadline)
                            .foregroundStyle(AppColors.subtext)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let pdfURL { shareItem = SettingsExportShareItem(url: pdfURL) }
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pdfURL == nil)
                .opacity(pdfURL == nil ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("Year-End Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Year", selection: Binding(
                            get: { year ?? years[0] },
                            set: { year = $0 }
                        )) {
                            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(year.map { String($0) } ?? "Year")
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        }
                    }
                    .accessibilityLabel("Tax year")
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url]) { shareItem = nil }
            }
            .task {
                if year == nil {
                    year = YearEndSummary.defaultYear(available: YearEndSummary.availableYears(store: store))
                }
            }
            .onChange(of: year) { _, newYear in
                if let newYear { generate(year: newYear) }
            }
        }
    }

    private func generate(year: Int) {
        pdfURL = nil
        failed = false
        let document = YearEndSummaryDocument.make(
            year: year,
            store: store,
            employee: friendsService.myUsername,
            company: companyName,
            companyLogo: logoManager.localImage
        )
        do {
            pdfURL = try document.writePDF()
        } catch {
            failed = true
        }
    }
}

private struct YearEndPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
