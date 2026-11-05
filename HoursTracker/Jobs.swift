import Foundation
import Combine

// MARK: - Multiple jobs
//
// The main job is the top-level `PaySettings` (so everything that predates
// jobs keeps working untouched); every other job is a `JobProfile` in
// `PaySettings.additionalJobs` with its own full copy of the pay rules —
// wage, pay schedule, cutoff and overtime. Each shift records its job, is
// paid by that job's rules, and lands in that job's cheque. Home's cheque
// card follows `HoursStore.chequeJobScope`: one job, or all of them.

struct JobProfile: Codable, Equatable, Identifiable, Hashable {
    static let primaryID = "primary"

    var id: String
    var name: String
    /// This job's pay rules. Its own `additionalJobs` is always empty.
    var settings: PaySettings

    static func == (lhs: JobProfile, rhs: JobProfile) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.settings == rhs.settings
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension HoursStore {
    static let allJobsScope = "all"
    private static let chequeScopeKey = "cheque_job_scope_v1"

    /// The main job first, then the others in the order they were added.
    var jobs: [JobProfile] {
        var main = paySettings
        main.additionalJobs = []
        let name = paySettings.primaryJobName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [JobProfile(id: JobProfile.primaryID, name: name.isEmpty ? "Main job" : name, settings: main)]
            + paySettings.additionalJobs
    }

    var hasMultipleJobs: Bool { !paySettings.additionalJobs.isEmpty }

    func job(id: String?) -> JobProfile {
        let all = jobs
        return all.first { $0.id == (id ?? JobProfile.primaryID) } ?? all[0]
    }

    /// The job a shift counts toward (a deleted job's shifts fall back to main).
    func jobID(of entry: WorkEntry) -> String { job(id: entry.jobID).id }

    /// Pay rules for this shift's job.
    func settings(for entry: WorkEntry) -> PaySettings {
        guard let id = entry.jobID, id != JobProfile.primaryID,
              let job = paySettings.additionalJobs.first(where: { $0.id == id }) else { return paySettings }
        return job.settings
    }

    // MARK: Editing

    /// Adds a job starting from the main job's rules (most people's second
    /// job pays on a similar schedule); returns it so the caller can edit it.
    @discardableResult
    func addJob(named name: String) -> JobProfile {
        var settings = paySettings
        settings.additionalJobs = []
        settings.primaryJobName = ""
        let job = JobProfile(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                             settings: settings)
        paySettings.additionalJobs.append(job)
        persist()
        return job
    }

    /// Saves a job's name and rules. The main job writes the top-level settings.
    func updateJob(_ job: JobProfile) {
        var rules = job.settings
        rules.additionalJobs = []
        if job.id == JobProfile.primaryID {
            let others = paySettings.additionalJobs
            rules.primaryJobName = job.name
            rules.additionalJobs = others
            paySettings = rules
        } else if let index = paySettings.additionalJobs.firstIndex(where: { $0.id == job.id }) {
            rules.primaryJobName = ""
            paySettings.additionalJobs[index] = JobProfile(id: job.id, name: job.name, settings: rules)
        }
        persist()
    }

    /// Removes a job; its shifts move to the main job so no hours are lost.
    func deleteJob(id: String) {
        guard id != JobProfile.primaryID else { return }
        paySettings.additionalJobs.removeAll { $0.id == id }
        for entry in entries where entry.jobID == id {
            var moved = entry
            moved.jobID = JobProfile.primaryID
            update(moved)
        }
        if chequeJobScope == id { chequeJobScope = JobProfile.primaryID }
        persist()
    }

    func shiftCount(forJob id: String) -> Int {
        entries.filter { !$0.isOffDay && jobID(of: $0) == id }.count
    }

    // MARK: Cheque scope

    /// What Home's cheque card (and the pay cycle screens) show: one job's id,
    /// or `allJobsScope`. Always the main job when there is only one.
    var chequeJobScope: String {
        get {
            guard hasMultipleJobs else { return JobProfile.primaryID }
            let saved = UserDefaults.standard.string(forKey: Self.chequeScopeKey) ?? JobProfile.primaryID
            if saved == Self.allJobsScope { return saved }
            return job(id: saved).id
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.chequeScopeKey)
        }
    }

    /// The job a new shift defaults to: the one on Home's cheque card, or the
    /// main job when the card shows every job.
    var defaultJobID: String {
        let scope = chequeJobScope
        return scope == Self.allJobsScope ? JobProfile.primaryID : scope
    }

    /// Schedule the cheque screens use: the chosen job's, or the main job's
    /// window when showing every job.
    var scopedPaySettings: PaySettings {
        let scope = chequeJobScope
        return scope == Self.allJobsScope ? paySettings : job(id: scope).settings
    }

    /// The shifts the cheque screens count: the chosen job's, or all of them.
    var scopedEntries: [WorkEntry] {
        let scope = chequeJobScope
        guard scope != Self.allJobsScope, hasMultipleJobs else { return entries }
        return entries.filter { jobID(of: $0) == scope }
    }

    var chequeScopeName: String {
        chequeJobScope == Self.allJobsScope ? "All jobs" : job(id: chequeJobScope).name
    }
}

extension PaySettings {
    /// Moves a past payday (and cutoff) forward to the next one on the same
    /// schedule. Returns false when nothing changed.
    mutating func rollPayDatesForward(today: Date = Date(), calendar cal: Calendar = .current) -> Bool {
        guard let payday = nextPayday else { return false }
        let start = cal.startOfDay(for: today)
        var current = cal.startOfDay(for: payday)
        let step = PayCycleEngine.spanDays(for: payPeriodType)
        var advances = 0
        while current <= start {
            guard let next = cal.date(byAdding: .day, value: step, to: current) else { break }
            current = next
            advances += 1
        }
        guard advances > 0, current != cal.startOfDay(for: payday) else { return false }
        nextPayday = current
        if PayCycleEngine.usesSavedCutoff(self), let cutoff = nextCutoff {
            var currentCutoff = cal.startOfDay(for: cutoff)
            for _ in 0..<advances {
                guard let next = cal.date(byAdding: .day, value: step, to: currentCutoff) else { break }
                currentCutoff = next
            }
            nextCutoff = currentCutoff
        }
        return true
    }
}
