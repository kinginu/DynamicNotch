// Reminders widget (Apple Reminders via EventKit, 2026-10-20). Replaces the in-app
// To-dos widget (TodoWidgetView, discarded with its SwiftData data — user decision).
//
// Layout (Apple-native, NookWidgetChrome): list name in the list colour with the open count on
// the right (like a list header in Reminders), a "New reminder…" field, then the incomplete
// reminders sorted by due date then creation: an empty circle (list colour when ticked, a second
// tap within the delay undoes it), the title, and the due date caption (red when overdue).
// Without access: "Allow Access" (first use) or "Open System Settings" (denied / restricted).
import SwiftUI
import EventKit

struct RemindersWidgetView: View {
    @StoredSetting(.remindersWidgetSettings) private var settings

    private var manager: RemindersManager { RemindersManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: NookWidgetMetrics.spacing) {
            if manager.hasAccess {
                header
                ReminderCreatorField(onAdd: { manager.add(title: $0) })
                    .disabled(manager.targetList == nil)
                content
            } else {
                accessView
            }
        }
        .nookWidgetFrame()
        .nookWidgetGalleryHook()
        .onAppear { manager.reload() }
        .onChange(of: settings.listIdentifiers) { _, _ in manager.reload() }
    }

    // MARK: - Header

    private var headerColor: Color {
        manager.shownLists.count == 1 ? (manager.shownLists.first?.color.color ?? .accentColor) : .accentColor
    }

    private var headerTitle: String {
        if manager.shownLists.count == 1, let list = manager.shownLists.first { return list.title }
        return String(localized: "Reminders")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(headerTitle)
                .font(.headline)
                .foregroundStyle(headerColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(manager.reminders.count, format: .number)
                .font(.headline.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityLabel(Text("\(manager.reminders.count) reminders"))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if manager.reminders.isEmpty {
            NookWidgetPlaceholder(systemImage: manager.isLoading ? "ellipsis" : "checkmark.circle",
                                  title: Text(manager.isLoading ? "" : String(localized: "No Reminders")))
        } else {
            // re-evaluates "overdue" once a minute while the Nook is open
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.reminders) { reminder in
                            ReminderRowView(
                                reminder: reminder,
                                now: context.date,
                                isCompleting: manager.completingIDs.contains(reminder.id),
                                showDueDate: settings.showDueDates,
                                showListColor: manager.shownLists.count > 1,
                                onToggle: { manager.toggleCompletion(reminder.id) }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        if let error = manager.lastError {
            NookWidgetFootnote(text: error, tone: .error)
        }
    }

    // MARK: - Access

    @ViewBuilder
    private var accessView: some View {
        let status = manager.authorizationStatus
        Group {
            if status == .notDetermined {
                NookWidgetAccessState(systemImage: "checklist", title: Text("Show your reminders here"),
                                      actionTitle: "Allow Access", prominent: true) {
                    Task { await manager.requestAccess() }
                }
            } else {
                NookWidgetAccessState(systemImage: "checklist", title: Text("No access to Reminders"),
                                      actionTitle: "Open System Settings", prominent: false) {
                    manager.openSystemSettings()
                }
            }
        }
        .onAppear { manager.refreshAuthorizationStatus() }
    }
}

// MARK: - Row

private struct ReminderRowView: View {
    let reminder: ReminderRow
    let now: Date
    let isCompleting: Bool
    let showDueDate: Bool
    let showListColor: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    private var circleColor: Color { reminder.listColor.color }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isCompleting ? "largecircle.fill.circle" : "circle")
                    .font(.body)
                    .foregroundStyle(isCompleting || showListColor
                                     ? AnyShapeStyle(circleColor) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleting ? Text("Mark as not done") : Text("Mark as done"))

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title.isEmpty ? String(localized: "New Reminder") : reminder.title)
                    .font(.subheadline)
                    .foregroundStyle(isCompleting ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                if showDueDate, let caption = dueCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(reminder.isOverdue(now: now) && !isCompleting
                                         ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .nookListRowBackground(highlighted: hovering, separatorInset: 28)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isCompleting)
        .accessibilityElement(children: .contain)
    }

    /// "Today", "Tomorrow, 15:00", "Oct 18" … like the Reminders app.
    private var dueCaption: String? {
        guard let due = reminder.dueDate else { return nil }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(due) {
            day = String(localized: "Today")
        } else if calendar.isDateInTomorrow(due) {
            day = String(localized: "Tomorrow")
        } else if calendar.isDateInYesterday(due) {
            day = String(localized: "Yesterday")
        } else if calendar.isDate(due, equalTo: now, toGranularity: .year) {
            day = due.formatted(.dateTime.month(.abbreviated).day())
        } else {
            day = due.formatted(.dateTime.year().month(.abbreviated).day())
        }
        guard reminder.dueHasTime else { return day }
        return "\(day), \(due.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - New reminder field

/// "New reminder…" field: plus.circle + plain text field on a quinary rounded field, accent focus
/// ring (like a focused macOS search field). Return adds the reminder and keeps the focus.
private struct ReminderCreatorField: View {
    var onAdd: (String) -> Void

    @State private var text = ""
    @FocusState private var isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.subheadline)
                .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            TextField("New reminder…", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isActive)
                .onSubmit {
                    let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    onAdd(title)
                    text = ""
                    isActive = true
                }
                .onExitCommand { text = ""; isActive = false }
                .accessibilityLabel(Text("New reminder"))
        }
        .nookFieldChrome(focused: isActive)
        .onTapGesture { isActive = true }
    }
}
