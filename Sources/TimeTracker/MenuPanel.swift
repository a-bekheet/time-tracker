import AppKit
import SwiftUI

struct MenuPanel: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""

    private var projects: [Project] { store.data.projects.filter { !$0.archived } }
    private var needsProject: Bool { projects.isEmpty && store.active == nil }
    private var matches: [Project] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return projects.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if needsProject { setupCard } else { timerCard }
            if store.reviewCount > 0 { reviewButton }
            if !projects.isEmpty { projectPicker }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 356)
        .onDisappear { search = "" }
    }

    private var setupCard: some View {
        HStack(alignment: .top, spacing: 12) {
            TrackerBadge(symbol: "timer", size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("Start tracking").font(.title3.weight(.semibold))
                Text("Create a project, then click it here to start a timer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .trackerSurface()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Time Tracker").font(.headline)
            Spacer()
            Menu {
                Button("New Project", systemImage: "folder.badge.plus") { showDashboard(.newProject) }
                Divider()
                Button("Quit Time Tracker", systemImage: "power") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
            .help("More actions")
        }
    }

    private var timerCard: some View {
        let active = store.active
        let project = active.flatMap { store.project($0.projectID) }
        let color = project.map { projectColor($0.color) } ?? .primary
        let elapsed = max(0, active?.start.map { store.now.timeIntervalSince($0) } ?? 0)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Label(active == nil ? "Timer idle" : "Tracking", systemImage: active == nil ? "circle" : "circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(TimerStatusLabelStyle(color: active == nil ? .secondary : color))
                Text(Duration.seconds(elapsed), format: .time(pattern: .hourMinuteSecond(padHourToLength: 2)))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(active == nil ? .secondary : .primary)
                    .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: Int(elapsed))
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(TimeFormat.duration(elapsed))
                Text(project?.name ?? (active == nil ? "Choose a project to start" : "Unknown project"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(project?.name ?? "")
            }
            Spacer(minLength: 0)
            if active != nil {
                Button { store.stop() } label: {
                    Label {
                        Text("Stop")
                    } icon: {
                        Image(systemName: "stop.fill").foregroundStyle(.red)
                    }
                }
                .trackerButtonStyle()
                .accessibilityLabel("Stop timer")
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18)
            shape.fill(.quaternary.opacity(0.45))
                .overlay { shape.fill(color.opacity(active == nil ? 0 : 0.08)) }
                .overlay { shape.strokeBorder(.quaternary, lineWidth: 1) }
        }
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Projects").font(.subheadline.weight(.semibold))
                Spacer()
                Button { showDashboard(.newProject) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("New project")
                .help("New project")
            }
            searchField
            if matches.isEmpty {
                Text("No matching projects")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(matches) { project in
                            ProjectPickerRow(project: project, isActive: store.active?.projectID == project.id) {
                                store.start(project.id)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(min(matches.count, 4)) * 44 - 2)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search projects", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear project search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var reviewButton: some View {
        Button { showDashboard(.review) } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(store.reviewCount == 1 ? "Review interrupted session" : "Review \(store.reviewCount) interrupted sessions")
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
        }
        .buttonStyle(PanelRowStyle(highlight: false))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { showDashboard() } label: {
                Label("Dashboard", systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity)
            }
            .trackerButtonStyle()
            if projects.isEmpty {
                Button { showDashboard(.newProject) } label: {
                    Label("New Project", systemImage: "plus")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .trackerButtonStyle(prominent: true)
                .tint(Color.trackerBlue)
            } else {
                Button { showDashboard(.addTime) } label: {
                    Label("Add Time", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .trackerButtonStyle()
                .help("Add a manual time entry")
            }
        }
        .controlSize(.large)
    }

    private func showDashboard(_ action: DashboardAction? = nil) {
        store.dashboardAction = action
        openWindow(id: "dashboard")
        NSApp.activate()
    }
}

private struct TimerStatusLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(color)
            configuration.title
        }
    }
}

private struct ProjectPickerRow: View {
    let project: Project
    let isActive: Bool
    let start: () -> Void

    var body: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                Circle().fill(projectColor(project.color)).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.callout.weight(.medium)).lineLimit(1)
                    if !project.code.isEmpty {
                        Text(project.code).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isActive ? "checkmark.circle.fill" : "play.fill")
                    .font(.system(size: isActive ? 14 : 10, weight: .semibold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
        }
        .buttonStyle(PanelRowStyle(highlight: isActive))
        .disabled(isActive)
        .accessibilityLabel(isActive ? "\(project.name), currently tracking" : "Start \(project.name)")
        .accessibilityValue(project.code)
        .help(isActive ? "Currently tracking \(project.name)" : "Start tracking \(project.name)")
    }
}

private struct PanelRowStyle: ButtonStyle {
    let highlight: Bool
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.primary.opacity(configuration.isPressed ? 0.12 : highlight || hovered ? 0.07 : 0))
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
