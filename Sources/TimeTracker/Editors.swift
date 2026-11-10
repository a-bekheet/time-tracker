import SwiftUI

struct ProjectEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var project: Project
    private let isNew: Bool
    private let colors = ["blue", "green", "orange", "purple", "red", "pink", "yellow", "gray"]

    init(project: Project?) {
        _project = State(initialValue: project ?? Project(name: ""))
        isNew = project == nil
    }

    private var name: String { project.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        EditorSheet(
            title: isNew ? "New Project" : "Edit Project",
            subtitle: isNew ? "Set up a project to track from the menu bar." : "Update how this project appears and tracks time.",
            symbol: isNew ? "folder.badge.plus" : "folder",
            actionTitle: isNew ? "Create Project" : "Save Changes",
            canSave: !name.isEmpty,
            save: save
        ) {
            EditorCard("Project details") {
                LabeledContent("Name") {
                    TextField("Project name", text: $project.name)
                        .accessibilityLabel("Name")
                }
                LabeledContent("Code") {
                    TextField("Optional", text: $project.code)
                        .accessibilityLabel("Project code")
                }
                Picker("Color", selection: $project.color) {
                    ForEach(colors, id: \.self) { color in
                        Label {
                            Text(color.capitalized)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(projectColor(color))
                        }
                        .tag(color)
                    }
                }
            }

            EditorCard("Tracking preferences") {
                Toggle("Continue tracking while Mac is asleep", isOn: $project.continueDuringSleep)
                Toggle("Archived", isOn: $project.archived)
            }
            .toggleStyle(.switch)
        }
    }

    private func save() {
        project.name = name
        store.put(project)
        dismiss()
    }
}

struct EntryEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var entry: Entry
    @State private var type: EntryType
    @State private var start: Date
    @State private var end: Date
    @State private var day: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var confirmOverlap = false
    private let isNew: Bool

    private enum EntryType: String, CaseIterable {
        case range = "Time range"
        case duration = "Daily duration"
    }

    init(entry: Entry?) {
        let now = Date()
        let value = entry ?? Entry(
            projectID: UUID(), day: Calendar.current.startOfDay(for: now), duration: 3600
        )
        _entry = State(initialValue: value)
        _type = State(initialValue: value.isTimed ? .range : .duration)
        _start = State(initialValue: value.start ?? now.addingTimeInterval(-3600))
        _end = State(initialValue: value.end ?? now)
        _day = State(initialValue: value.day)
        _hours = State(initialValue: Int(value.duration) / 3600)
        _minutes = State(initialValue: Int(value.duration) % 3600 / 60)
        isNew = entry == nil
    }

    private var candidate: Entry {
        var result = entry
        switch type {
        case .range:
            result.start = start
            result.end = end
            result.day = Calendar.current.startOfDay(for: start)
            result.duration = end.timeIntervalSince(start)
        case .duration:
            result.start = nil
            result.end = nil
            result.day = Calendar.current.startOfDay(for: day)
            result.duration = TimeInterval(hours) * 3600 + TimeInterval(minutes) * 60
        }
        result.needsReview = false
        return result
    }

    private var validationMessage: String? {
        guard store.project(entry.projectID) != nil else { return "Choose a project." }
        switch type {
        case .range:
            return end > start ? nil : "The end time must be after the start time."
        case .duration:
            let valid = hours >= 0 && (0..<60).contains(minutes) && (hours > 0 || minutes > 0)
            guard valid else { return "Enter a positive duration with minutes between 0 and 59." }
            return Int(exactly: candidate.duration) == nil ? "Enter a smaller duration." : nil
        }
    }

    var body: some View {
        EditorSheet(
            title: isNew ? "Add Time" : "Edit Entry",
            subtitle: isNew ? "Log time you spent on a project." : "Update the project, timing, or note for this entry.",
            symbol: "timer",
            actionTitle: isNew ? "Add Time" : "Save Changes",
            canSave: validationMessage == nil,
            save: submit
        ) {
            if entry.needsReview {
                notice("This session was interrupted. Choose an end time to include it in reports.", symbol: "exclamationmark.triangle", color: .orange)
            } else if store.active?.id == entry.id {
                notice("Saving will stop the running timer at the chosen end time.", symbol: "info.circle", color: .accentColor)
            }

            EditorCard("Time details") {
                Picker("Project", selection: $entry.projectID) {
                    ForEach(store.reportProjects.filter { !$0.archived || $0.id == entry.projectID }) {
                        Text($0.name).tag($0.id)
                    }
                }
                Picker("Entry type", selection: $type) {
                    ForEach(EntryType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if type == .range {
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                } else {
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                    LabeledContent("Duration") {
                        HStack(spacing: 8) {
                            TextField("Hours", value: $hours, format: .number)
                                .frame(width: 52)
                                .accessibilityLabel("Hours")
                            Text("hours").foregroundStyle(.secondary)
                            TextField("Minutes", value: $minutes, format: .number)
                                .frame(width: 52)
                                .accessibilityLabel("Minutes")
                            Text("minutes").foregroundStyle(.secondary)
                        }
                    }
                }

                LabeledContent("Note") {
                    TextField("Optional", text: $entry.note).accessibilityLabel("Note")
                }
            }

            if let validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if isNew, let project = store.data.projects.first(where: { !$0.archived }) {
                entry.projectID = project.id
            }
        }
        .alert("Overlapping time", isPresented: $confirmOverlap) {
            Button("Save anyway", action: save)
            Button("Go back", role: .cancel) {}
        } message: {
            Text("This time range overlaps another timed entry. Saving both will count both durations in reports.")
        }
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            TrackerBadge(symbol: symbol, color: color, size: 28)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(10)
        .trackerSurface(tint: color)
    }

    private func submit() {
        if store.overlaps(candidate) { confirmOverlap = true } else { save() }
    }

    private func save() {
        store.put(candidate)
        dismiss()
    }
}

private struct EditorSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let symbol: String
    let actionTitle: String
    let canSave: Bool
    let save: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TrackerBadge(symbol: symbol, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 24, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            content

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .trackerButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text(actionTitle).foregroundStyle(canSave ? Color.white : Color.secondary)
                }
                .trackerButtonStyle(prominent: true)
                .tint(.trackerBlue)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 500)
    }
}

private struct EditorCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) { content }
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trackerSurface()
    }
}
