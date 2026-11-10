import Foundation

@main struct CoreChecks {
    @MainActor static func main() throws {
        let start = Date(timeIntervalSince1970: 1000), boundary = start.addingTimeInterval(1800), end = boundary.addingTimeInterval(2700)
        let timed = Entry(projectID: UUID(), start: start, end: end, day: start, duration: 4500)
        precondition(timed.seconds(in: DateInterval(start: start, end: boundary)) == 1800)
        precondition(timed.seconds(in: DateInterval(start: boundary, end: end)) == 2700)
        let daily = Entry(projectID: UUID(), day: start, duration: 5400)
        precondition(daily.seconds(in: DateInterval(start: start, end: start.addingTimeInterval(86400))) == 5400)
        precondition(daily.seconds(in: DateInterval(start: start.addingTimeInterval(86400), end: start.addingTimeInterval(172800))) == 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = Store(url: url, observeSystem: false)
        let first = Project(name: "First"), second = Project(name: "Second", continueDuringSleep: true)
        store.put(first); store.put(second); store.start(first.id, at: start); store.start(second.id, at: start.addingTimeInterval(120))
        precondition(store.data.entries.first?.duration == 120)
        store.sleep(at: start.addingTimeInterval(180)); precondition(store.active?.projectID == second.id)
        let reopened = Store(url: url, observeSystem: false)
        precondition(reopened.active == nil && reopened.reviewCount == 1)
        reopened.start(first.id, at: start.addingTimeInterval(240)); reopened.sleep(at: start.addingTimeInterval(300))
        precondition(reopened.active == nil && reopened.data.entries.last?.duration == 60)
        try checkProjectDeletion(in: url.deletingLastPathComponent())
        print("Core checks passed: switching, sleep, recovery, midnight allocation, daily durations, and project deletion.")
    }

    @MainActor private static func checkProjectDeletion(in directory: URL) throws {
        let url = directory.appendingPathComponent("deletion.json")
        let store = Store(url: url, observeSystem: false)
        let archived = Project(name: "Archived", archived: true)
        let retained = Project(name: "Retained", code: "R-01", color: "blue", archived: true)
        let active = Project(name: "Active")
        let archivedEntry = Entry(projectID: archived.id, day: Date(), duration: 1800)
        let retainedEntry = Entry(projectID: retained.id, day: Date(), duration: 2700)
        let activeEntry = Entry(projectID: active.id, day: Date(), duration: 3600)
        store.put(archived)
        store.put(retained)
        store.put(active)
        store.put(archivedEntry)
        store.put(retainedEntry)
        store.put(activeEntry)

        precondition(!store.deleteArchivedProject(active.id, keepEntries: true))
        precondition(store.deleteArchivedProject(archived.id, keepEntries: false))
        precondition(store.deleteArchivedProject(retained.id, keepEntries: true))
        let reopened = Store(url: url, observeSystem: false)
        precondition(reopened.data.projects == [active])
        precondition(reopened.data.entries.map(\.id) == [retainedEntry.id, activeEntry.id])
        precondition(reopened.reportProjects == [active, retained])
        precondition(reopened.project(retained.id) == retained)
        precondition(reopened.csv().contains("\"Retained\",\"R-01\""))
        reopened.start(retained.id)
        precondition(reopened.active == nil)
        reopened.delete(retainedEntry)
        precondition(reopened.project(retained.id) == nil)

        // A file where the parent directory should be makes the write fail.
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let unwritable = Store(url: blocker.appendingPathComponent("data.json"), observeSystem: false)
        unwritable.data = TrackerData(projects: [archived], entries: [archivedEntry])
        unwritable.error = nil
        precondition(!unwritable.deleteArchivedProject(archived.id, keepEntries: true))
        precondition(unwritable.error != nil)
        precondition(unwritable.data.projects == [archived])
        precondition(unwritable.data.entries.map(\.id) == [archivedEntry.id])
    }
}
