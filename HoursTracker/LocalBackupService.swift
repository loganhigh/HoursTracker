import Foundation

// MARK: - On-device full snapshot (Application Support)

enum LocalBackupError: LocalizedError {
    case cannotCreateDirectory
    case encodingFailed
    case decodingFailed
    case unsupportedVersion(Int)
    case fileMissing
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory: return "Could not create backup folder."
        case .encodingFailed: return "Could not save backup."
        case .decodingFailed: return "Backup file is damaged or unreadable."
        case .unsupportedVersion(let v): return "This backup was made with a newer app version (\(v))."
        case .fileMissing: return "No backup found. Tap Back Up Data first."
        case .writeFailed: return "Could not write backup files."
        }
    }
}

/// Full app snapshot for local restore (same device). Binary plist for `Data` (certificate/award images).
struct HoursTrackerLocalBackup: Codable {
    static let formatVersion = 1

    var version: Int
    var createdAt: Date
    var entries: [WorkEntry]
    var yearArchives: [YearArchive]
    var paySettings: PaySettings
    var payHistoryEntries: [PayHistoryEntry]
    var certificateEntries: [CertificateEntry]
    var awardEntries: [AwardEntry]
    var gamificationProfile: GamificationProfile
    /// Certificate image files keyed by filename (same as `CertificateEntry.filename`).
    var certificateFiles: [String: Data]
    /// Award image files keyed by filename.
    var awardFiles: [String: Data]
}

enum LocalBackupService {
    private static let backupFilename = "hours_tracker_local_backup.plist"

    static func backupDirectoryURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("HoursTracker", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func backupFileURL() throws -> URL {
        try backupDirectoryURL().appendingPathComponent(backupFilename, isDirectory: false)
    }

    static func backupExists() -> Bool {
        (try? backupFileURL()).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static func lastBackupDate() -> Date? {
        guard let url = try? backupFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let d = vals.contentModificationDate else { return nil }
        return d
    }

    static func makeBackup(from store: HoursStore) throws -> HoursTrackerLocalBackup {
        var certificateFiles: [String: Data] = [:]
        for c in store.certificateEntries {
            if let u = store.certificateFileURL(for: c.filename),
               let data = try? Data(contentsOf: u) {
                certificateFiles[c.filename] = data
            }
        }
        var awardFiles: [String: Data] = [:]
        for a in store.awardEntries {
            if let u = store.awardFileURL(for: a.filename),
               let data = try? Data(contentsOf: u) {
                awardFiles[a.filename] = data
            }
        }
        return HoursTrackerLocalBackup(
            version: HoursTrackerLocalBackup.formatVersion,
            createdAt: Date(),
            entries: store.entries,
            yearArchives: store.yearArchives,
            paySettings: store.paySettings,
            payHistoryEntries: store.payHistoryEntries,
            certificateEntries: store.certificateEntries,
            awardEntries: store.awardEntries,
            gamificationProfile: store.gamificationProfile,
            certificateFiles: certificateFiles,
            awardFiles: awardFiles
        )
    }

    static func writeBackup(_ backup: HoursTrackerLocalBackup) throws {
        let enc = PropertyListEncoder()
        enc.outputFormat = .binary
        let data: Data
        do {
            data = try enc.encode(backup)
        } catch {
            throw LocalBackupError.encodingFailed
        }
        let url = try backupFileURL()
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw LocalBackupError.writeFailed
        }
    }

    static func readBackup() throws -> HoursTrackerLocalBackup {
        let url = try backupFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocalBackupError.fileMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LocalBackupError.fileMissing
        }
        let backup: HoursTrackerLocalBackup
        do {
            backup = try PropertyListDecoder().decode(HoursTrackerLocalBackup.self, from: data)
        } catch {
            throw LocalBackupError.decodingFailed
        }
        guard backup.version == HoursTrackerLocalBackup.formatVersion else {
            throw LocalBackupError.unsupportedVersion(backup.version)
        }
        return backup
    }
}
