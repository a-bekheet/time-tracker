import SwiftUI
import AppKit

@main struct TimeTrackerApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra {
            MenuPanel().environmentObject(store)
        } label: {
            if let entry = store.active, let start = entry.start {
                Label {
                    Text("\(store.project(entry.projectID)?.name ?? "Timer") · \(TimeFormat.duration(store.now.timeIntervalSince(start)))")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "timer")
                }
            } else { Label("Time Tracker", systemImage: "clock") }
        }.menuBarExtraStyle(.window)
        Window("Time Tracker", id: "dashboard") {
            MainView().environmentObject(store).frame(minWidth: 850, minHeight: 580)
        }.defaultSize(width: 1050, height: 700)
    }
}
func projectColor(_ name: String) -> Color {
    switch name { case "red": return .red; case "orange": return .orange; case "yellow": return .yellow; case "green": return .green; case "purple": return .purple; case "pink": return .pink; case "gray": return .gray; default: return .blue }
}
