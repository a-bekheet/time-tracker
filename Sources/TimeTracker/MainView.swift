import SwiftUI
import Charts

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview", trend = "Daily Trend", timesheet = "Timesheet"
    case history = "History", projects = "Projects", archive = "Archive"

    var id: Self { self }
    var isReport: Bool { self == .overview || self == .trend || self == .timesheet }

    var symbol: String {
        switch self {
        case .overview: "chart.pie"
        case .trend: "chart.bar.xaxis"
        case .timesheet: "tablecells"
        case .history: "clock.arrow.circlepath"
        case .projects: "folder"
        case .archive: "archivebox"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "See where your time went."
        case .trend: "See how much time you tracked each day."
        case .timesheet: "Compare daily hours across projects."
        case .history: "Review and edit your time entries."
        case .projects: "Manage the projects you track from the menu bar."
        case .archive: "Manage archived projects."
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: DashboardSection? = .overview
    @State private var projectEditor: EditorPresentation<Project>?
    @State private var projectToDelete: Project?
    @State private var entryEditor: EditorPresentation<Entry>?
    @State private var period = "This week"
    @State private var from = Calendar.current.startOfDay(for: Date())
    @State private var to = Calendar.current.startOfDay(for: Date())
    @State private var filter: UUID?

    private var section: DashboardSection { selection ?? .overview }
    private var hasActiveProjects: Bool { store.data.projects.contains { !$0.archived } }

    private var range: DateInterval {
        let calendar = Calendar.current
        switch period {
        case "Today": return calendar.dateInterval(of: .day, for: store.now)!
        case "This month": return calendar.dateInterval(of: .month, for: store.now)!
        case "Custom":
            let start = calendar.startOfDay(for: min(from, to))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, to)))!
            return DateInterval(start: start, end: end)
        default: return calendar.dateInterval(of: .weekOfYear, for: store.now)!
        }
    }

    private var entries: [Entry] {
        let interval = range
        return store.data.entries.filter {
            !$0.needsReview && (filter == nil || $0.projectID == filter)
                && $0.seconds(in: interval, now: store.now) > 0
        }
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let interval = range
        var result: [Date] = []
        var day = interval.start
        while day < interval.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Reports") { sidebarRows(DashboardSection.allCases.filter(\.isReport)) }
                Section("Manage") { sidebarRows(DashboardSection.allCases.filter { !$0.isReport }) }
            }
            .listStyle(.sidebar)
            .navigationTitle("Time Tracker")
            .navigationSplitViewColumnWidth(min: 155, ideal: 176, max: 230)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    if store.reviewCount > 0 { reviewBanner }
                    if section.isReport { reportFilters }
                    switch section {
                    case .overview: overview
                    case .trend: trend
                    case .timesheet: timesheet
                    case .history: history
                    case .projects: projectList(archived: false)
                    case .archive: projectList(archived: true)
                    }
                }
                .frame(maxWidth: 1000)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.export() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                        .help("Export time entries as CSV")
                }
            }
        }
        .onChange(of: store.dashboardAction, initial: true) { _, action in
            guard let action else { return }
            store.dashboardAction = nil
            switch action {
            case .addTime: addTime()
            case .newProject: newProject()
            case .review: filter = nil; selection = .history
            }
        }
        .sheet(item: $projectEditor) { presentation in
            ProjectEditor(project: presentation.value)
        }
        .sheet(item: $entryEditor) { presentation in
            EntryEditor(entry: presentation.value)
        }
        .onChange(of: filter.flatMap(store.project)?.id) { _, availableID in
            if availableID == nil { filter = nil }
        }
        .alert(
            "Delete project?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            presenting: projectToDelete
        ) { project in
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            if projectEntryCount(project) > 0 {
                Button("Keep Time Entries", role: .destructive) {
                    store.deleteArchivedProject(project.id, keepEntries: true)
                }
                Button("Delete Time Entries", role: .destructive) {
                    store.deleteArchivedProject(project.id, keepEntries: false)
                }
            } else {
                Button("Delete Project", role: .destructive) {
                    store.deleteArchivedProject(project.id, keepEntries: false)
                }
            }
        } message: { project in
            Text(projectDeletionMessage(project))
        }
        .alert("Time Tracker", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func sidebarRows(_ sections: [DashboardSection]) -> some View {
        ForEach(sections) { item in
            Label(item.rawValue, systemImage: item.symbol).tag(item)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.rawValue).font(.system(size: 32, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(section.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            headerAction("New Project", symbol: "folder.badge.plus", prominent: !hasActiveProjects, action: newProject)
            if hasActiveProjects {
                headerAction("Add Time", symbol: "plus", prominent: true, action: addTime)
            }
        }
        .controlSize(.large)
    }

    private func headerAction(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .trackerButtonStyle(prominent: prominent)
        .tint(prominent ? .trackerBlue : nil)
    }

    private var reportFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Picker("Period", selection: $period) {
                    ForEach(["Today", "This week", "This month", "Custom"], id: \.self) { Text($0) }
                }
                .frame(maxWidth: 185)

                Picker("Project", selection: $filter) {
                    Text("All projects").tag(nil as UUID?)
                    ForEach(store.reportProjects) { Text($0.name).tag(Optional($0.id)) }
                }
                .frame(maxWidth: 245)
                Spacer(minLength: 0)
            }

            if period == "Custom" {
                HStack(spacing: 14) {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                }
            }
        }
        .font(.callout)
        .padding(12)
        .trackerSurface()
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            TrackerBadge(symbol: "exclamationmark.triangle", color: .orange, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.reviewCount == 1 ? "One session needs review" : "\(store.reviewCount) sessions need review")
                    .font(.callout.weight(.semibold))
                Text("Set an end time to include interrupted sessions in reports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review") { filter = nil; selection = .history }.trackerButtonStyle()
        }
        .padding(12)
        .trackerSurface(tint: .orange)
    }

    private var overview: some View {
        let interval = range
        let reportEntries = entries
        let grouped = Dictionary(grouping: reportEntries, by: \.projectID)
        let totals = store.reportProjects.compactMap { project -> ProjectTotal? in
            guard let items = grouped[project.id] else { return nil }
            return ProjectTotal(project: project, seconds: seconds(for: items, in: interval))
        }.sorted { $0.seconds > $1.seconds }
        let total = seconds(for: reportEntries, in: interval)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                TrackerBadge(symbol: "timer", size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tracked time").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Text(TimeFormat.duration(total))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(reportDates).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !totals.isEmpty {
                    Text(totals.count == 1 ? "1 project" : "\(totals.count) projects")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                }
            }
            .padding(18)
            .trackerSurface(tint: .accentColor)

            if totals.isEmpty {
                noTrackedTime
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("By project").font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(totals) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ProjectDot(color: item.project.color)
                                Text(item.project.name).font(.callout.weight(.medium))
                                Spacer()
                                Text(TimeFormat.duration(item.seconds)).font(.callout.monospacedDigit())
                                Text((item.seconds / total).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(minWidth: 42, alignment: .trailing)
                            }
                            ProgressView(value: item.seconds, total: total)
                                .tint(projectColor(item.project.color))
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(18)
                .trackerSurface()
            }
        }
    }

    private var reportDates: String {
        let interval = range
        let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)!
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return interval.start == end
            ? interval.start.formatted(format)
            : "\(interval.start.formatted(format)) – \(end.formatted(format))"
    }

    private var trend: some View {
        let reportEntries = entries
        return VStack(alignment: .leading, spacing: 14) {
            if reportEntries.isEmpty {
                noTrackedTime
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hours per day").font(.headline).accessibilityAddTraits(.isHeader)
                    Chart(days, id: \.self) { day in
                        let hours = seconds(for: reportEntries, in: dayInterval(day)) / 3600
                        BarMark(x: .value("Day", day, unit: .day), y: .value("Hours", hours))
                            .foregroundStyle(Color.trackerBlue.gradient)
                            .cornerRadius(4)
                    }
                    .chartYAxisLabel("Hours")
                    .frame(height: 310)
                }
                .padding(18)
                .trackerSurface()
            }
        }
    }

    private var timesheet: some View {
        let grouped = Dictionary(grouping: entries, by: \.projectID)
        let dates = days
        let interval = range
        return Group {
            if grouped.isEmpty {
                noTrackedTime
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hours by project").font(.headline).accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal) {
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("Project").frame(width: 142, alignment: .leading)
                                ForEach(dates, id: \.self) { day in
                                    Text(day.formatted(.dateTime.month(.abbreviated).day())).frame(width: 62)
                                }
                                Text("Total").frame(width: 72)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            Divider()
                            ForEach(store.reportProjects) { project in
                                if let items = grouped[project.id] {
                                    GridRow {
                                        Button {
                                            filter = project.id
                                            selection = .history
                                        } label: {
                                            HStack(spacing: 7) {
                                                ProjectDot(color: project.color)
                                                Text(project.name).lineLimit(1)
                                            }
                                        }
                                        .buttonStyle(.link)
                                        .help("Show entries for \(project.name)")
                                        .frame(width: 142, alignment: .leading)

                                        ForEach(dates, id: \.self) { day in
                                            let value = seconds(for: items, in: dayInterval(day))
                                            Text(value > 0 ? TimeFormat.duration(value) : "—")
                                                .foregroundStyle(value > 0 ? .primary : .secondary)
                                                .frame(width: 62)
                                        }
                                        Text(TimeFormat.duration(seconds(for: items, in: interval)))
                                            .fontWeight(.semibold).frame(width: 72)
                                    }
                                }
                            }
                        }
                        .font(.callout.monospacedDigit())
                        .padding(.bottom, 6)
                    }
                }
                .padding(18)
                .trackerSurface()
            }
        }
    }

    private var history: some View {
        let visible = store.data.entries.filter { filter == nil || $0.projectID == filter }
            .sorted { ($0.start ?? $0.day) > ($1.start ?? $1.day) }
        return VStack(alignment: .leading, spacing: 12) {
            if let filter, let project = store.project(filter) {
                HStack {
                    ProjectDot(color: project.color)
                    Text(project.name).font(.callout.weight(.semibold))
                    Spacer()
                    Button("Show All") { self.filter = nil }.trackerButtonStyle()
                }
                .padding(12)
                .trackerSurface()
            }
            if visible.isEmpty {
                emptyCard("No entries yet", detail: "Start a timer from the menu bar or add time manually.", symbol: "clock.arrow.circlepath")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { entry in
                        if entry.id != visible.first?.id { Divider().padding(.leading, 36) }
                        historyRow(entry)
                    }
                }
                .padding(.horizontal, 16)
                .trackerSurface()
            }
        }
    }

    private func historyRow(_ entry: Entry) -> some View {
        let project = store.project(entry.projectID)
        let running = store.active?.id == entry.id
        return HStack(spacing: 12) {
            ProjectDot(color: project?.color ?? "gray")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(project?.name ?? "Unknown project").font(.callout.weight(.semibold))
                    if entry.needsReview { status("Needs review", color: .orange) }
                    if running { status("Running", color: .green) }
                }
                Text(entryDate(entry)).font(.caption).foregroundStyle(.secondary)
                if !entry.note.isEmpty { Text(entry.note).font(.caption) }
            }
            Spacer(minLength: 8)
            Text(entry.needsReview ? "—" : TimeFormat.duration(entry.start.map {
                max(0, (entry.end ?? store.now).timeIntervalSince($0))
            } ?? entry.duration))
            .font(.callout.monospacedDigit().weight(.medium))
            Button("Edit") { entryEditor = EditorPresentation(value: entry) }.trackerButtonStyle()
            Button(role: .destructive) { store.delete(entry) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete entry")
                .help("Delete entry")
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private func projectList(archived: Bool) -> some View {
        let projects = store.data.projects.filter { $0.archived == archived }
        if projects.isEmpty {
            if archived {
                emptyCard("No archived projects", detail: "Use the Archive button next to a project in Projects.", symbol: "archivebox")
            } else if store.data.projects.isEmpty {
                emptyCard("Create your first project", detail: "Projects appear here and in your menu bar.", symbol: "folder.badge.plus")
            } else {
                emptyCard("No active projects", detail: "Create a project or restore one from Archive.", symbol: "folder")
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(projects) { project in
                    if project.id != projects.first?.id { Divider().padding(.leading, 36) }
                    projectRow(project)
                }
            }
            .padding(.horizontal, 16)
            .trackerSurface()
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let archiveAction = project.archived ? "Restore" : "Archive"
        return HStack(spacing: 12) {
            ProjectDot(color: project.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.callout.weight(.semibold))
                if !project.code.isEmpty { Text(project.code).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Label(
                project.continueDuringSleep ? "Continues during sleep" : "Stops on sleep",
                systemImage: "moon"
            )
            .font(.caption).foregroundStyle(.secondary)
            Button("Edit") { projectEditor = EditorPresentation(value: project) }.trackerButtonStyle()
            Button(archiveAction) {
                var updated = project
                updated.archived.toggle()
                store.put(updated)
            }
            .trackerButtonStyle()
            .accessibilityLabel("\(archiveAction) \(project.name)")
            if project.archived {
                Button(role: .destructive) { projectToDelete = project } label: {
                    Text("Delete").foregroundStyle(.red)
                }
                .trackerButtonStyle()
                .accessibilityLabel("Delete \(project.name)")
            }
        }
        .padding(.vertical, 12)
    }

    private func projectEntryCount(_ project: Project) -> Int {
        store.data.entries.filter { $0.projectID == project.id }.count
    }

    private func projectDeletionMessage(_ project: Project) -> String {
        let count = projectEntryCount(project)
        let projectName = "“\(project.name)”"
        guard count > 0 else { return "\(projectName) will be permanently deleted." }
        let entries = count == 1 ? "1 time entry" : "\(count) time entries"
        return "\(projectName) will be permanently deleted. Choose whether to keep its \(entries) in History and reports."
    }

    private var noTrackedTime: some View {
        emptyCard(
            hasActiveProjects ? "No tracked time for this period" : "Start tracking",
            detail: hasActiveProjects
                ? "Try another period, start a timer from the menu bar, or add time manually."
                : "Create a project, then select it in the menu bar to start a timer.",
            symbol: hasActiveProjects ? "clock" : "folder.badge.plus"
        )
    }

    private func emptyCard(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TrackerBadge(symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .trackerSurface()
    }

    private func status(_ title: String, color: Color) -> some View {
        Text(title).font(.caption.weight(.medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func seconds(for entries: [Entry], in interval: DateInterval) -> TimeInterval {
        entries.reduce(0) { $0 + $1.seconds(in: interval, now: store.now) }
    }

    private func dayInterval(_ day: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .day, for: day)!
    }

    private func entryDate(_ entry: Entry) -> String {
        guard let start = entry.start else {
            return "\(entry.day.formatted(date: .abbreviated, time: .omitted)) · Daily duration"
        }
        let end = entry.end?.formatted(date: .abbreviated, time: .shortened)
            ?? (entry.needsReview ? "end unknown" : "now")
        return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end)"
    }

    private func addTime() { entryEditor = EditorPresentation(value: nil) }
    private func newProject() { projectEditor = EditorPresentation(value: nil) }
}

private struct EditorPresentation<Value>: Identifiable {
    let id = UUID()
    let value: Value?
}

private struct ProjectTotal: Identifiable {
    let project: Project
    let seconds: TimeInterval
    var id: UUID { project.id }
}

private struct ProjectDot: View {
    let color: String
    var body: some View {
        Circle().fill(projectColor(color)).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}
