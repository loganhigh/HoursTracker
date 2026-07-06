import Foundation

/// Feature flags for the phased Firestore architecture migration.
enum FirebaseMigrationFlags {
    private static let defaults = UserDefaults.standard

    /// Write entries to `users/{uid}/timeEntries` (primary path).
    static var useTimeEntriesPath: Bool {
        if defaults.object(forKey: "ff_use_time_entries") == nil { return true }
        return defaults.bool(forKey: "ff_use_time_entries")
    }

    /// Dual-write mirror to legacy `users/{uid}/entries` during rollout.
    static var useLegacyEntryMirror: Bool {
        if defaults.object(forKey: "ff_legacy_entry_mirror") == nil { return false }
        return defaults.bool(forKey: "ff_legacy_entry_mirror")
    }

    /// Home UI reads `users/{uid}/stats/*` instead of recomputing from entries.
    static var useServerStats: Bool {
        if defaults.object(forKey: "ff_use_server_stats") == nil { return true }
        return defaults.bool(forKey: "ff_use_server_stats")
    }

    /// Skip `saveProfileSnapshot` on every entry CRUD (server maintains public profile).
    static var skipProfileSnapshotOnEntryCRUD: Bool {
        if defaults.object(forKey: "ff_skip_profile_on_entry") == nil { return true }
        return defaults.bool(forKey: "ff_skip_profile_on_entry")
    }

    /// Client publishes activity events (disabled once Cloud Functions own activity).
    static var emitClientActivityEvents: Bool {
        if defaults.object(forKey: "ff_client_activity") == nil { return false }
        return defaults.bool(forKey: "ff_client_activity")
    }

    /// Friends list reads `publicProfiles/{uid}` — the server-maintained single
    /// source of truth — instead of the private, dual-written `users/{uid}` doc.
    ///
    /// ON by default: the backfill is complete (every user has a populated
    /// `publicProfiles` doc), and `mergePublicProfile` falls back to the
    /// `users/{uid}` doc for any friend whose public doc is somehow missing, so
    /// nobody can vanish from the list. Reading the server-owned doc means a
    /// stale or old-build client can never clobber the level/stats friends see —
    /// security rules deny all client writes to `publicProfiles`.
    static var usePublicProfilesForFriends: Bool {
        if defaults.object(forKey: "ff_public_profiles") == nil { return true }
        return defaults.bool(forKey: "ff_public_profiles")
    }

    /// `friendships/{pairId}` is the canonical relationship source.
    /// Backfill runs on first sign-in to populate from legacy friends.
    static var useFriendshipsCollection: Bool {
        if defaults.object(forKey: "ff_friendships") == nil { return true }
        return defaults.bool(forKey: "ff_friendships")
    }
}
