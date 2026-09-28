import PDFKit
import SwiftUI

/// Previews a cheque's pay period as a PDF statement and shares the file.
/// Presented from the share button on PayCycleDetailView.
struct PayPeriodStatementSheet: View {
    @ObservedObject var store: HoursStore
    let cycle: PayCycle

    @Environment(\.dismiss) private var dismiss
    @AppStorage("company_name") private var companyName: String = ""
    @ObservedObject private var logoManager = CompanyLogoManager.shared
    @ObservedObject private var friendsService = FriendsService.shared

    @State private var pdfURL: URL?
    @State private var failed = false
    @State private var shareItem: SettingsExportShareItem?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.bg.ignoresSafeArea()
                if let pdfURL {
                    PDFPreview(url: pdfURL)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.top, 8)
                        .padding(.bottom, 96)
                } else if failed {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Couldn't create the PDF",
                        subtitle: "Please try again."
                    )
                } else {
                    ProgressView().tint(AppTheme.Colors.accent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let pdfURL { shareItem = SettingsExportShareItem(url: pdfURL) }
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.Colors.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(pdfURL == nil)
                .opacity(pdfURL == nil ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("Pay Statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url]) { shareItem = nil }
            }
            .task { generate() }
        }
    }

    private func generate() {
        let statement = PayPeriodStatement.make(
            cycle: cycle,
            store: store,
            employee: friendsService.myUsername,
            company: companyName,
            companyLogo: logoManager.localImage
        )
        do {
            pdfURL = try statement.writePDF()
        } catch {
            failed = true
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
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
