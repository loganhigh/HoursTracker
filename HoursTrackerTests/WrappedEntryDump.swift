import XCTest
import SwiftUI
@testable import HoursTracker

/// Renders the two Wrapped entry points so they can be eyeballed outside
/// January. Skipped unless WRAPPED_DUMP_DIR is set.
@MainActor
final class WrappedEntryDump: XCTestCase {
    func testDumpEntryPoints() throws {
        guard let dir = ProcessInfo.processInfo.environment["WRAPPED_DUMP_DIR"] else {
            throw XCTSkip("Set WRAPPED_DUMP_DIR")
        }
        let stats = WrappedPreviewData.busyYear

        let card = ZStack {
            AppColors.bg
            VStack(spacing: 16) {
                WrappedHomeCard(
                    year: 2026,
                    totalHours: stats.totalHours,
                    username: "logan",
                    onOpen: {}, onDismiss: {}
                )
                WrappedHomeCard(
                    year: 2026,
                    totalHours: stats.totalHours,
                    username: nil,
                    onOpen: {}, onDismiss: {}
                )
            }
            .padding(16)
        }
        .frame(width: 390, height: 260)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let data = renderer.uiImage?.pngData() {
            try data.write(to: URL(fileURLWithPath: "\(dir)/home-card.png"))
        }
    }
}
