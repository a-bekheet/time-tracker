import Foundation
import AppKit
import SwiftUI

enum DashboardAction { case addTime, newProject, review }

@MainActor final class Store: ObservableObject {
    @Published var data = TrackerData()
    @Published var now = Date()
    @Published var error: String?
    @Published var dashboardAction: DashboardAction?
    private let url: URL
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    init(url: URL? = nil, observeSystem: Bool = true) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TimeTracker/data.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { data = try JSONDecoder().decode(TrackerData.self, from: Data(contentsOf: self.url)) }
            catch { self.error = "Could not read your saved data. No changes will be saved until the problem is resolved: \(error.localizedDescription)"; readFailed = true }
        }
        // An open session at launch has an unknown end. Preserve it for explicit review.
        for i in data.entries.indices where data.entries[i].end == nil && data.entries[i].start != nil {
            data.entries[i].needsReview = true
        }
        save()
        if observeSystem {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sleep() } })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.now = Date() } })
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
        }
    }
    private var readFailed = false
    var active: Entry? { data.entries.first { $0.start != nil && $0.end == nil && !$0.needsReview } }
    var reviewCount: Int { data.entries.filter(\.needsReview).count }
    var reportProjects: [Project] { data.projects + (data.retainedProjects ?? []) }
    func project(_ id: UUID) -> Project? {
        data.projects.first { $0.id == id } ?? data.retainedProjects?.first { $0.id == id }
    }
    func save() {
        guard !readFailed else { return }
        persist(data)
    }
    @discardableResult
    private func persist(_ snapshot: TrackerData) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            return true
        } catch {
            self.error = "Could not save your data: \(error.localizedDescription)"
            return false
        }
    }
    func start(_ id: UUID, at date: Date = Date()) {
        guard data.projects.contains(where: { $0.id == id && !$0.archived }) else { return }
        stop(at: date)
        data.entries.append(Entry(projectID: id, start: date, day: Calendar.current.startOfDay(for: date), duration: 0))
        now = date; save()
    }
    func stop(at date: Date = Date()) {
        guard let id = active?.id, let i = data.entries.firstIndex(where: { $0.id == id }), let start = data.entries[i].start else { return }
        data.entries[i].end = max(start, date); data.entries[i].duration = max(0, date.timeIntervalSince(start)); now = date; save()
    }
    func sleep(at date: Date = Date()) { if let active, project(active.projectID)?.continueDuringSleep != true { stop(at: date) } }
    func put(_ project: Project) {
        if let i = data.projects.firstIndex(where: { $0.id == project.id }) { data.projects[i] = project } else { data.projects.append(project) }
        if project.archived && active?.projectID == project.id { stop() }
        save()
    }
    func put(_ entry: Entry) {
        if let i = data.entries.firstIndex(where: { $0.id == entry.id }) { data.entries[i] = entry } else { data.entries.append(entry) }
        pruneRetainedProjects()
        save()
    }
    func delete(_ entry: Entry) {
        data.entries.removeAll { $0.id == entry.id }
        pruneRetainedProjects()
        save()
    }

    private func pruneRetainedProjects() {
        guard let retained = data.retainedProjects else { return }
        let projectIDs = Set(data.entries.map(\.projectID))
        let remaining = retained.filter { projectIDs.contains($0.id) }
        if remaining.count != retained.count {
            data.retainedProjects = remaining.isEmpty ? nil : remaining
        }
    }

    @discardableResult
    func deleteArchivedProject(_ id: UUID, keepEntries: Bool) -> Bool {
        guard let project = data.projects.first(where: { $0.id == id && $0.archived }) else { return false }
        guard !readFailed else {
            error = "Could not delete the project because the saved data could not be read."
            return false
        }

        var updated = data
        updated.projects.removeAll { $0.id == id }
        if keepEntries {
            if updated.entries.contains(where: { $0.projectID == id }) {
                updated.retainedProjects = (updated.retainedProjects ?? []) + [project]
            }
        } else {
            updated.entries.removeAll { $0.projectID == id }
        }
        guard persist(updated) else { return false }
        data = updated
        return true
    }

    func overlaps(_ entry: Entry) -> Bool {
        guard let start = entry.start, let end = entry.end else { return false }
        return data.entries.contains { other in
            guard other.id != entry.id, let s = other.start, !other.needsReview else { return false }
            let e = other.end ?? now
            return start < e && s < end
        }
    }
    func csv() -> String {
        let iso = ISO8601DateFormatter(); let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.locale = Locale(identifier: "en_US_POSIX")
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows = ["project,code,type,date,start,end,duration_seconds,note,needs_review"]
        for e in data.entries {
            let p = project(e.projectID)
            let duration = e.start.map { max(0, (e.end ?? now).timeIntervalSince($0)) } ?? e.duration
            rows.append([p?.name ?? "Unknown", p?.code ?? "", e.isTimed ? "timed" : "daily duration", day.string(from: e.day), e.start.map(iso.string) ?? "", e.end.map(iso.string) ?? "", (e.needsReview ? "" : String(Int(duration))), e.note, e.needsReview ? "true" : "false"].map(quote).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "time-tracker.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        if panel.runModal() == .OK, let url = panel.url { do { try csv().write(to: url, atomically: true, encoding: .utf8) } catch { self.error = "Export failed: \(error.localizedDescription)" } }
    }
}
