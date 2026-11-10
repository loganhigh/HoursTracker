import Foundation
import CoreLocation
import UserNotifications
import Combine

// MARK: - Arrive at work → start a live shift
//
// The user saves the places they work (a pin + a name). iOS watches those
// places itself with geofences (`CLMonitor`): the app is not tracking
// location and does no work until the phone actually crosses one. Then:
//
//   - Arriving, with no live shift running: one push per place per day —
//     "You're at Main Yard. Start your live shift?" with Start now /
//     In 15 min. Tapping it opens a sheet where the start can be now, the
//     moment they arrived, or any time they pick (got there early, start
//     at 7).
//   - Leaving, with a live shift running there: "Leaving Main Yard? Clock
//     out?" — Clock out uses the time they left, not the time they tap.
//
// Needs "Always" location permission (geofences only fire in the
// background with it). Asked for only when the user turns the feature on.

struct ArrivalSite: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var latitude: Double
    var longitude: Double
    /// Metres. iOS treats anything under ~100 m as 100 m.
    var radius: Double = 150
    var enabled: Bool = true

    static let radiusOptions: [Double] = [100, 150, 250, 400]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var place: ShiftPlace { ShiftPlace(name: name, latitude: latitude, longitude: longitude) }
}

/// A tapped arrival push: where, and when they got there.
struct ArrivalPrompt: Identifiable, Equatable {
    let siteID: String
    let arrivedAt: Date
    var id: String { "\(siteID)-\(arrivedAt.timeIntervalSince1970)" }
}

@MainActor
final class ArrivalMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = ArrivalMonitor()

    private static let monitorName = "HourTrackerArrivals"
    private static let sitesKey = "arrival_sites_v1"
    private static let enabledKey = "arrival_alerts_enabled"
    private static let promptedKey = "arrival_prompted_v1"
    /// Set while the geofence monitor is being created, cleared once it
    /// exists. Still set at the next launch = that creation took the app
    /// down, so the feature switches itself off rather than crash again.
    private static let startingKey = "arrival_monitor_starting"
    /// iOS allows 20 monitored regions per app.
    static let maxSites = 20

    static let arrivalCategory = "SHIFT_ARRIVAL"
    static let departureCategory = "SHIFT_DEPARTURE"
    static let startNowAction = "SHIFT_START_NOW"
    static let snoozeAction = "SHIFT_START_LATER"
    static let clockOutAction = "SHIFT_CLOCK_OUT"
    static let keepWorkingAction = "SHIFT_KEEP_WORKING"

    /// Notification actions for the arrival and departure pushes.
    static var notificationCategories: [UNNotificationCategory] {
        [
            UNNotificationCategory(
                identifier: arrivalCategory,
                actions: [
                    UNNotificationAction(identifier: startNowAction, title: "Start now", options: []),
                    UNNotificationAction(identifier: snoozeAction, title: "Remind me in 15 min", options: []),
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: departureCategory,
                actions: [
                    UNNotificationAction(identifier: clockOutAction, title: "Clock out", options: [.foreground]),
                    UNNotificationAction(identifier: keepWorkingAction, title: "Still working", options: []),
                ],
                intentIdentifiers: []
            ),
        ]
    }

    @Published private(set) var sites: [ArrivalSite]
    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var monitor: CLMonitor?
    /// The one in-flight `CLMonitor` creation. iOS kills the app if two
    /// monitors with the same name exist, and at launch `start()` and the
    /// authorization callback both sync at once — they must share this.
    private var monitorCreation: Task<CLMonitor, Never>?
    /// Syncs run one at a time; a request during a sync re-runs it after.
    private var isSyncing = false
    private var needsResync = false
    private var eventsTask: Task<Void, Never>?
    /// iOS 18+: keeps background region events flowing (`CLServiceSession`).
    private var serviceSession: AnyObject?
    /// Set while turning the feature on, so the When-In-Use answer can be
    /// followed straight away by the Always request.
    private var wantsAlways = false

    private override init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.sitesKey),
           let saved = try? JSONDecoder().decode([ArrivalSite].self, from: data) {
            sites = saved
        } else {
            sites = []
        }
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        authorization = .notDetermined
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    /// True when iOS will deliver geofence events in the background.
    var hasAlwaysPermission: Bool { authorization == .authorizedAlways }

    // MARK: Lifecycle

    /// Call at launch. iOS relaunches the app in the background when a
    /// geofence fires; the monitor has to be reopened (same name) for the
    /// event to be delivered.
    func start() {
        if UserDefaults.standard.bool(forKey: Self.startingKey) {
            UserDefaults.standard.removeObject(forKey: Self.startingKey)
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return
        }
        guard isEnabled, sites.contains(where: \.enabled) else { return }
        Task { await syncMonitor() }
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { requestAlwaysPermission() }
        Task { await syncMonitor() }
    }

    /// When-In-Use first (iOS requires it), then Always. Already-denied
    /// permission can only be changed in the Settings app.
    func requestAlwaysPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            wantsAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse, self.wantsAlways {
                self.wantsAlways = false
                self.manager.requestAlwaysAuthorization()
            }
            await self.syncMonitor()
        }
    }

    // MARK: Sites

    func save(_ site: ArrivalSite) {
        var site = site
        site.name = String(site.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SavedLocationsStore.nameLimit))
        guard !site.name.isEmpty else { return }
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        } else {
            guard sites.count < Self.maxSites else { return }
            sites.append(site)
        }
        // The name also belongs in the shift location list.
        SavedLocationsStore.add(site.name)
        persistSites()
        Task { await syncMonitor() }
    }

    func remove(_ site: ArrivalSite) {
        sites.removeAll { $0.id == site.id }
        persistSites()
        Task { await syncMonitor() }
    }

    func site(id: String) -> ArrivalSite? { sites.first { $0.id == id } }

    private func persistSites() {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: Self.sitesKey)
        }
    }

    // MARK: Monitoring

    /// Brings iOS's watched regions in line with the enabled sites.
    private func syncMonitor() async {
        // One sync at a time. Main-actor isolated, so this check-and-set has
        // no suspension point between them.
        if isSyncing { needsResync = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            needsResync = false
            await performSync()
        } while needsResync
    }

    /// The single monitor for this app, created at most once.
    private func sharedMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        if let monitorCreation { return await monitorCreation.value }
        UserDefaults.standard.set(true, forKey: Self.startingKey)
        let creation = Task { await CLMonitor(Self.monitorName) }
        monitorCreation = creation
        let created = await creation.value
        UserDefaults.standard.removeObject(forKey: Self.startingKey)
        monitor = created
        return created
    }

    private func performSync() async {
        let wanted = isEnabled ? sites.filter(\.enabled) : []
        if wanted.isEmpty {
            if let monitor {
                for id in await monitor.identifiers { await monitor.remove(id) }
            }
            eventsTask?.cancel()
            eventsTask = nil
            serviceSession = nil
            return
        }
        let monitor = await sharedMonitor()
        if #available(iOS 18.0, *), serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .always)
        }
        let wantedIDs = Set(wanted.map(\.id))
        for id in await monitor.identifiers where !wantedIDs.contains(id) {
            await monitor.remove(id)
        }
        for site in wanted {
            // Re-adding replaces the condition, so moved pins and new radii apply.
            let condition = CLMonitor.CircularGeographicCondition(center: site.coordinate, radius: site.radius)
            await monitor.add(condition, identifier: site.id, assuming: .unsatisfied)
        }
        if eventsTask == nil {
            eventsTask = Task { [weak self] in
                do {
                    for try await event in await monitor.events {
                        guard let self else { return }
                        self.handle(siteID: event.identifier, state: event.state, at: event.date)
                    }
                } catch {
                    // The stream ends if permission is withdrawn; the next
                    // sync (permission change, launch) starts a new one.
                }
                self?.eventsTask = nil
            }
        }
    }

    private func handle(siteID: String, state: CLMonitor.Event.State, at date: Date) {
        guard isEnabled, let site = site(id: siteID), site.enabled else { return }
        switch state {
        case .satisfied: arrived(at: site, date: date)
        case .unsatisfied: left(site, date: date)
        default: break
        }
    }

    // MARK: Prompts

    private func arrived(at site: ArrivalSite, date: Date) {
        guard LiveShiftManager.shared.activeShift == nil else { return }
        // Once per place per day: walking out to the truck and back in
        // shouldn't ask again.
        let today = Self.dayKey(Date())
        var prompted = UserDefaults.standard.dictionary(forKey: Self.promptedKey) as? [String: String] ?? [:]
        guard prompted[site.id] != today else { return }
        // Already logged a shift today (by hand): nothing to start.
        if let store = HoursStore.current,
           store.entries.contains(where: { !$0.isOffDay && Calendar.current.isDateInToday($0.date) }) {
            return
        }
        prompted[site.id] = today
        UserDefaults.standard.set(prompted, forKey: Self.promptedKey)
        postArrival(site: site, arrivedAt: date, delay: nil)
    }

    private func left(_ site: ArrivalSite, date: Date) {
        // Leaving before the arrival push was answered: drop any snoozed one.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["arrival.\(site.id)"])
        guard let shift = LiveShiftManager.shared.activeShift else { return }
        // Only a shift at this place (or one with no place set).
        if let name = shift.locationName, !name.isEmpty,
           name.caseInsensitiveCompare(site.name) != .orderedSame { return }
        // Popping out within 20 minutes of starting isn't the end of a shift.
        guard shift.elapsedWorked(at: date) >= 20 * 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Leaving \(site.name)?"
        let worked = AppTheme.Format.hours(shift.elapsedWorked(at: date) / 3600)
        content.body = "Your live shift has been running \(worked). Clock out at \(date.formatted(date: .omitted, time: .shortened))?"
        content.sound = .default
        content.categoryIdentifier = Self.departureCategory
        content.userInfo = ["kind": "shiftDeparture", "siteID": site.id, "leftAt": date.timeIntervalSince1970]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "departure.\(site.id)", content: content, trigger: nil)
        )
    }

    /// The arrival push, now or after a snooze.
    func postArrival(site: ArrivalSite, arrivedAt: Date, delay: TimeInterval?) {
        let content = UNMutableNotificationContent()
        content.title = "You're at \(site.name)"
        content.body = "Start your live shift? Tap to pick a start time."
        content.sound = .default
        content.categoryIdentifier = Self.arrivalCategory
        content.userInfo = ["kind": "shiftArrival", "siteID": site.id, "arrivedAt": arrivedAt.timeIntervalSince1970]
        let trigger = delay.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "arrival.\(site.id)", content: content, trigger: trigger)
        )
    }

    // MARK: Notification responses

    /// Handles the arrival/departure pushes. Returns false for anything else.
    func handleResponse(actionID: String, userInfo: [AnyHashable: Any]) -> Bool {
        guard let kind = userInfo["kind"] as? String,
              kind == "shiftArrival" || kind == "shiftDeparture",
              let siteID = userInfo["siteID"] as? String else { return false }
        let site = site(id: siteID)
        let router = NotificationRouter.shared

        if kind == "shiftArrival" {
            let arrivedAt = (userInfo["arrivedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            switch actionID {
            case Self.startNowAction:
                LiveShiftManager.shared.clockIn(at: Date(), place: site?.place)
            case Self.snoozeAction:
                if let site, LiveShiftManager.shared.activeShift == nil {
                    postArrival(site: site, arrivedAt: arrivedAt, delay: 15 * 60)
                }
            case UNNotificationDismissActionIdentifier:
                break
            default:
                // Tapped: choose when the shift started.
                if LiveShiftManager.shared.activeShift == nil {
                    router.arrivalPrompt = ArrivalPrompt(siteID: siteID, arrivedAt: arrivedAt)
                } else {
                    router.openAddShift = true
                }
            }
            return true
        }

        let leftAt = (userInfo["leftAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        switch actionID {
        case Self.clockOutAction:
            router.clockOutLiveShiftAt = leftAt
        case Self.keepWorkingAction, UNNotificationDismissActionIdentifier:
            break
        default:
            router.openAddShift = true
        }
        return true
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
