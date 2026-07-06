import SwiftUI

// MARK: - Sync Status Indicator
struct SyncStatusView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var cloudSync: CloudSyncManager
    
    var body: some View {
        HStack(spacing: 6) {
            if !networkMonitor.isConnected {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            } else if cloudSync.isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.subtext)
            } else if cloudSync.pendingChanges > 0 {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("\(cloudSync.pendingChanges) pending")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            } else if cloudSync.lastSyncDate != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("Synced")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(AppTheme.Colors.card.opacity(0.6))
        )
    }
}
