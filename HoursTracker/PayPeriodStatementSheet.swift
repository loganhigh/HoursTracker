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
                AppColors.bg.ignoresSafeArea()
                if let pdfURL {
                    // The statement sits on a quiet card; the owl peeks over
                    // the card's edge (PDFKit's own inset above the page would
                    // leave him floating if he stood on the paper itself).
                    PDFPreview(url: pdfURL)
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
                        .owlStanding(.clipboard)
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
                        OwlView(pose: .clipboard, size: .emptyState)
                        LoadingDots()
                        Text("Drawing up your statement…")
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
            .navigationTitle("Hours Statement")
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
