import Foundation

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var code = ""
    var color = "blue"
    var continueDuringSleep = false
    var archived = false
}
struct Entry: Codable, Identifiable {
    var id = UUID()
    var projectID: UUID
    var start: Date?
    var end: Date?
    var day: Date
    var duration: TimeInterval
    var note = ""
    var needsReview = false
    var isTimed: Bool { start != nil }
    func seconds(in range: DateInterval, now: Date = Date()) -> TimeInterval {
        if let start {
            let end = self.end ?? now
            return max(0, min(end, range.end).timeIntervalSince(max(start, range.start)))
        }
        return day >= range.start && day < range.end ? duration : 0
    }
}
struct TrackerData: Codable {
    var projects: [Project] = []
    var entries: [Entry] = []
    // Metadata for entries kept after their project was deleted.
    var retainedProjects: [Project]?
}

enum TimeFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
}
