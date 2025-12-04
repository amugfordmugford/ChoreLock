import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - Models
struct Kid: Identifiable, Codable {
    var id = UUID()
    let name: String
    
    // Templates
    var weekdayTasks: [TaskItem]
    var weekendTasks: [TaskItem]
    
    // Working list for today
    var currentTasks: [TaskItem]
    
    // Bookkeeping
    var lastCompletedDate: Date?
    var lastLoadedDay: Date?
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isCompleted: Bool = false
}

// A single completion log entry
struct CompletionLogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let kidName: String
    let timestamp: Date
}

// MARK: - Logic
class GatekeeperLogic: ObservableObject {
    // Singleton instance so AppDelegate and SwiftUI share the same logic object
    static let shared = GatekeeperLogic()
    
    @Published var kids: [Kid]
    @Published var isLocked: Bool = true
    @Published var assignedKidName: String = UserDefaults.standard.string(forKey: "assignedKidName") ?? "" {
        didSet {
            UserDefaults.standard.set(assignedKidName, forKey: "assignedKidName")
            ensureTodayTasksLoaded()
            scheduleCheckLockStatus()
        }
    }
    
    // Admin authentication state (used to allow quitting)
    @Published var isAdminAuthenticated: Bool = false
    
    // Completion log, newest first (persisted)
    @Published var completionLog: [CompletionLogEntry] = [] {
        didSet {
            persistCompletionLog()
        }
    }
    
    // CONFIGURATION: chore window (24h) — now hard-coded; no customization in UI or UserDefaults
    let startHour: Int = 06  // 6 AM
    let endHour: Int = 09    // 9 AM
    
    // Persistence keys and retention
    private let completionLogKey = "completionLog"
    private let retentionDays: Int = 14
    
    // Window readiness (prevents early NSWindow mutations during launch)
    @Published private(set) var windowReady: Bool = false
    
    var currentKidIndex: Int? {
        kids.firstIndex(where: { $0.name == assignedKidName })
    }
    
    // Make init private to enforce singleton usage
    private init() {
        // Your original "tasks" become weekdayTasks. Weekend defaults to a copy.
        let micahWeekday = [
            TaskItem(title: "Brush Teeth"),
            TaskItem(title: "Change Clothes")
        ]
        let aidanWeekday = [
            TaskItem(title: "Brush Teeth"),
            TaskItem(title: "Feed the Cats"),
            TaskItem(title: "Change Clothes")
        ]
        
        let micahWeekend = micahWeekday // start with same list; editable in Admin
        let aidanWeekend = aidanWeekday // start with same list; editable in Admin
        
        let todayIsWeekend = Self.isWeekend(Date())
        
        self.kids = [
            Kid(
                name: "Micah",
                weekdayTasks: micahWeekday,
                weekendTasks: micahWeekend,
                currentTasks: todayIsWeekend ? micahWeekend.map { TaskItem(title: $0.title, isCompleted: false) }
                                             : micahWeekday.map { TaskItem(title: $0.title, isCompleted: false) },
                lastCompletedDate: nil,
                lastLoadedDay: Calendar.current.startOfDay(for: Date())
            ),
            Kid(
                name: "Aidan",
                weekdayTasks: aidanWeekday,
                weekendTasks: aidanWeekend,
                currentTasks: todayIsWeekend ? aidanWeekend.map { TaskItem(title: $0.title, isCompleted: false) }
                                             : aidanWeekday.map { TaskItem(title: $0.title, isCompleted: false) },
                lastCompletedDate: nil,
                lastLoadedDay: Calendar.current.startOfDay(for: Date())
            )
        ]
        
        // Load persisted log and prune to retention window
        loadCompletionLog()
        pruneOldLogEntries()
        
        // Do NOT call checkLockStatus() yet; we’ll call it after windowReady.
        
        // Keep checking hourly/minutely to react to time window transitions
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.scheduleCheckLockStatus()
        }
    }
    
    // Called from setupWindow once the window exists
    @MainActor
    func markWindowReady() {
        guard !windowReady else { return }
        windowReady = true
        // Now that the window is ready, evaluate lock state
        checkLockStatus()
    }
    
    // Determine if a date is weekend using user's locale/calendar
    static func isWeekend(_ date: Date) -> Bool {
        Calendar.current.isDateInWeekend(date)
    }
    
    // Ensure currentTasks reflect today and correct day type
    func ensureTodayTasksLoaded() {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let weekend = Self.isWeekend(now)
        
        for i in kids.indices {
            let needsReload: Bool = kids[i].lastLoadedDay != todayStart
            if needsReload {
                let template = weekend ? kids[i].weekendTasks : kids[i].weekdayTasks
                kids[i].currentTasks = template.map { TaskItem(title: $0.title, isCompleted: false) }
                kids[i].lastLoadedDay = todayStart
                kids[i].lastCompletedDate = nil
            } else {
                let usingWeekendTemplate = kids[i].currentTasks.matchesTemplate(of: weekend ? kids[i].weekendTasks : kids[i].weekdayTasks)
                if !usingWeekendTemplate {
                    let template = weekend ? kids[i].weekendTasks : kids[i].weekdayTasks
                    kids[i].currentTasks = template.map { TaskItem(title: $0.title, isCompleted: false) }
                }
            }
        }
    }
    
    // Schedule to avoid re-entrancy; run on main after current runloop turn
    private func scheduleCheckLockStatus() {
        DispatchQueue.main.async { [weak self] in
            self?.checkLockStatus()
        }
    }
    
    func checkLockStatus() {
        // Don’t mutate NSWindow until it exists and is ready
        guard windowReady else { return }
        
        ensureTodayTasksLoaded()
        
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        let isChoreTime = hour >= startHour && hour < endHour
        
        if !isChoreTime {
            unlockScreen()
            return
        }
        
        if let index = currentKidIndex {
            if let lastDate = kids[index].lastCompletedDate {
                let lastDateStart = calendar.startOfDay(for: lastDate)
                let today = calendar.startOfDay(for: now)
                
                if lastDateStart == today {
                    unlockScreen()
                } else {
                    kids[index].lastCompletedDate = nil
                    ensureTodayTasksLoaded()
                    lockScreen()
                }
            } else {
                lockScreen()
            }
        } else {
            lockScreen()
        }
    }
    
    func markCurrentKidDone() {
        if let index = currentKidIndex {
            kids[index].lastCompletedDate = Date()
            // Log the completion
            let entry = CompletionLogEntry(kidName: kids[index].name, timestamp: Date())
            completionLog.insert(entry, at: 0)
            pruneOldLogEntries()
            scheduleCheckLockStatus()
        }
    }
    
    // IMPORTANT: Only run after windowReady is true
    func lockScreen() {
        guard windowReady else { return }
        DispatchQueue.main.async {
            self.isLocked = true
            NSApp.activate(ignoringOtherApps: true)
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.setMenuHidden(true)
            }
            if let window = NSApplication.shared.windows.first {
                // Ensure the window is visible when locking
                if !window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                }
                CATransaction.begin()
                window.styleMask = [.borderless]
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.level = .mainMenu + 1
                window.backgroundColor = NSColor.white
                window.isMovable = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                if let screen = NSScreen.main { window.setFrame(screen.frame, display: true) }
                window.makeKeyAndOrderFront(nil)
                CATransaction.commit()
            }
        }
    }
    
    func unlockScreen() {
        guard windowReady else { return }
        DispatchQueue.main.async {
            self.isLocked = false
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.setMenuHidden(false)
            }
            if let window = NSApplication.shared.windows.first {
                CATransaction.begin()
                // Keep the window capable of being full-size content if we ever show it.
                window.styleMask = [.titled, .fullSizeContentView]
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.level = .normal
                CATransaction.commit()
                
                // Order the window out so the desktop is visible when unlocked.
                window.orderOut(nil)
            }
            // Hide the app while unlocked to avoid a stray small blank window on reactivation.
            NSApp.hide(nil)
        }
    }
    
    // MARK: - Admin: add/remove/edit tasks in templates
    func addTask(toWeekend: Bool, for kidIndex: Int) {
        let newTitle = "New Task"
        if toWeekend {
            kids[kidIndex].weekendTasks.append(TaskItem(title: newTitle))
        } else {
            kids[kidIndex].weekdayTasks.append(TaskItem(title: newTitle))
        }
    }
    
    func removeTasks(at offsets: IndexSet, toWeekend: Bool, for kidIndex: Int) {
        if toWeekend {
            kids[kidIndex].weekendTasks.remove(atOffsets: offsets)
        } else {
            kids[kidIndex].weekdayTasks.remove(atOffsets: offsets)
        }
    }
    
    func resetTodayFromTemplate(for kidIndex: Int, weekend: Bool) {
        let template = weekend ? kids[kidIndex].weekendTasks : kids[kidIndex].weekdayTasks
        kids[kidIndex].currentTasks = template.map { TaskItem(title: $0.title, isCompleted: false) }
        kids[kidIndex].lastCompletedDate = nil
        kids[kidIndex].lastLoadedDay = Calendar.current.startOfDay(for: Date())
        scheduleCheckLockStatus()
    }
    
    // MARK: - Persistence
    private func persistCompletionLog() {
        do {
            let data = try JSONEncoder().encode(completionLog)
            UserDefaults.standard.set(data, forKey: completionLogKey)
        } catch {
            // Swallow errors in this simple sample
        }
    }
    
    private func loadCompletionLog() {
        guard let data = UserDefaults.standard.data(forKey: completionLogKey) else { return }
        do {
            let loaded = try JSONDecoder().decode([CompletionLogEntry].self, from: data)
            completionLog = loaded
        } catch {
            completionLog = []
        }
    }
    
    private func pruneOldLogEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date().addingTimeInterval(-14 * 24 * 3600)
        completionLog = completionLog.filter { $0.timestamp >= cutoff }
    }
    
    // MARK: - Launch at Login (best-effort presence)
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // In production, present an error or guidance (System Settings > Login Items)
        }
    }
    
    var isLaunchAtLoginEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
    }
    
    func updateLaunchAtLoginFlag(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "launchAtLoginEnabled")
        setLaunchAtLogin(enabled)
    }
}

// Helper to compare currentTasks shape to a template by titles (ignoring completion)
private extension Array where Element == TaskItem {
    func matchesTemplate(of template: [TaskItem]) -> Bool {
        let selfTitles = self.map { $0.title }
        let templateTitles = template.map { $0.title }
        return selfTitles == templateTitles
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject var logic = GatekeeperLogic.shared
    @State private var pinInput = ""
    @State private var showError = false
    @State private var showSuccessMessage = false
    @State private var isAdminMode = false
    
    @State private var adminSelectedDayType: DayType = Calendar.current.isDateInWeekend(Date()) ? .weekend : .weekday
    
    let parentPin = "8585"

    var body: some View {
        ZStack {
            if logic.isLocked {
                Color.white
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer(minLength: 0)
                    
                    VStack(spacing: 16) {
                        Group {
                            if showSuccessMessage {
                                VStack(spacing: 20) {
                                    Text("🎉").font(.system(size: 96))
                                    Text("Awesome. Have a great day!")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(Color.green)
                                }
                            } else if isAdminMode {
                                adminView
                            } else if let index = logic.currentKidIndex {
                                taskListView(for: index)
                            } else {
                                VStack(spacing: 8) {
                                    Text("🔒 Device Locked")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Parent setup required.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        
                        if !showSuccessMessage && !isAdminMode {
                            footerView
                                .padding(.top, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                // When unlocked, don't render a visible background. The window will be hidden and app is hidden.
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        // Defer initial window setup until the window actually exists
        .background(WindowReady {
            setupWindow()
        })
        .onAppear {
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                logic.checkLockStatus()
            }
        }
    }
    
    var adminView: some View {
        VStack(spacing: 18) {
            Text("Parent Settings")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)
            
            // Launch window controls removed; times are hard-coded in the app.
            VStack(alignment: .leading, spacing: 10) {
                Text("Chore Time Window")
                    .font(.headline)
                Text("Active daily from 13:00 to 22:00")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Toggle(isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "launchAtLoginEnabled") },
                    set: { newValue in
                        logic.updateLaunchAtLoginFlag(newValue)
                    })) {
                    Text("Launch at Login")
                }
                .help("Helps ensure the app is running at the specified time daily.")
            }
            .frame(maxWidth: 520)
            .padding()
            .background(Color(white: 0.97))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.9), lineWidth: 1)
            )
            
            Text("Whose computer is this?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Kid picker
            HStack(spacing: 16) {
                ForEach(logic.kids) { kid in
                    Button(action: { logic.assignedKidName = kid.name }) {
                        VStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(logic.assignedKidName == kid.name ? .white : .gray)
                                .frame(width: 44, height: 44)
                                .background(logic.assignedKidName == kid.name ? Color.accentColor : Color(white: 0.9))
                                .clipShape(Circle())
                            Text(kid.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(width: 120, height: 120)
                        .background(Color(white: 0.96))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(logic.assignedKidName == kid.name ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Day type selector
            Picker("Day Type", selection: $adminSelectedDayType) {
                Text("WEEKDAYS").tag(DayType.weekday)
                Text("WEEKEND").tag(DayType.weekend)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            
            // Editable task list for selected template
            if let idx = logic.currentKidIndex {
                EditableTemplateList(
                    tasks: Binding(
                        get: {
                            adminSelectedDayType == .weekday ? logic.kids[idx].weekdayTasks : logic.kids[idx].weekendTasks
                        },
                        set: { newValue in
                            if adminSelectedDayType == .weekday {
                                logic.kids[idx].weekdayTasks = newValue
                            } else {
                                logic.kids[idx].weekendTasks = newValue
                            }
                        }
                    ),
                    addAction: {
                        logic.addTask(toWeekend: adminSelectedDayType == .weekend, for: idx)
                    },
                    removeAction: { offsets in
                        logic.removeTasks(at: offsets, toWeekend: adminSelectedDayType == .weekend, for: idx)
                    }
                )
                .frame(width: 460)
                
                Button {
                    logic.resetTodayFromTemplate(for: idx, weekend: adminSelectedDayType == .weekend)
                } label: {
                    Text("Reset Today From \(adminSelectedDayType == .weekday ? "Weekday" : "Weekend") Template")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                Text("Select a kid to edit tasks.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Admin-only Completion Log
            VStack(alignment: .leading, spacing: 8) {
                Text("Completion Log (last 14 days)")
                    .font(.headline)
                if logic.completionLog.isEmpty {
                    Text("No completions yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(logic.completionLog.prefix(50)) { entry in
                            HStack {
                                Text(entry.kidName)
                                    .font(.body)
                                Spacer()
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(white: 0.97))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(white: 0.9), lineWidth: 1)
                    )
                    .frame(maxWidth: 520)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            
            // Done
            Button(action: {
                isAdminMode = false
                // Leaving Admin ends authentication unless you want it to persist
                logic.isAdminAuthenticated = false
            }) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.98))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }
    
    func taskListView(for index: Int) -> some View {
        VStack(spacing: 20) {
            Text("Hi, \(logic.kids[index].name)!")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(logic.kids[index].currentTasks.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Button(action: {
                            logic.kids[index].currentTasks[i].isCompleted.toggle()
                            if logic.kids[index].currentTasks.allSatisfy({ $0.isCompleted }) {
                                withAnimation { showSuccessMessage = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                    showSuccessMessage = false
                                    logic.markCurrentKidDone()
                                }
                            }
                        }) {
                            Image(systemName: logic.kids[index].currentTasks[i].isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(logic.kids[index].currentTasks[i].isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Text(logic.kids[index].currentTasks[i].title)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(16)
            .background(Color(white: 0.97))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(white: 0.9), lineWidth: 1)
            )
            .frame(width: 520)
        }
        .frame(maxWidth: .infinity)
    }
    
    var footerView: some View {
        HStack(spacing: 12) {
            SecureField("Parent PIN", text: $pinInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            
            Button {
                if pinInput == parentPin {
                    isAdminMode = true
                    logic.isAdminAuthenticated = true
                    pinInput = ""
                }
            } label: {
                Text("Admin")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.92))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if !isAdminMode {
                Button {
                    if pinInput == parentPin {
                        logic.isAdminAuthenticated = true
                        logic.unlockScreen()
                        pinInput = ""
                    }
                } label: {
                    Text("Unlock")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    func setupWindow() {
        guard let window = NSApplication.shared.windows.first else {
            return
        }
        // Establish a safe baseline window configuration
        window.styleMask = [.titled, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = NSColor.white
        window.isMovable = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main { window.setFrame(screen.frame, display: true) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if logic.isLocked {
            window.level = .mainMenu + 1
        } else {
            window.level = .normal
            // Immediately hide the window when unlocked.
            window.orderOut(nil)
            // And keep the app hidden to avoid stray window on reopen while unlocked.
            NSApp.hide(nil)
        }
        
        Task { @MainActor in
            GatekeeperLogic.shared.markWindowReady()
        }
    }
}

// Helper to run code once a window exists
struct WindowReady: NSViewRepresentable {
    let onReady: () -> Void
    init(_ onReady: @escaping () -> Void) { self.onReady = onReady }
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onReady() }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum DayType {
    case weekday
    case weekend
}

// Editable template list component
struct EditableTemplateList: View {
    @Binding var tasks: [TaskItem]
    let addAction: () -> Void
    let removeAction: (IndexSet) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: addAction) {
                    Label("Add Task", systemImage: "plus.circle.fill")
                        .labelStyle(.titleOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            List {
                ForEach(tasks.indices, id: \.self) { i in
                    HStack {
                        TextField("Task title", text: Binding(
                            get: { tasks[i].title },
                            set: { tasks[i].title = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        Spacer()
                        Button {
                            removeAction(IndexSet(integer: i))
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this task")
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: removeAction)
            }
            .frame(height: 240)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.97))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(white: 0.9), lineWidth: 1)
            )
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var originalMainMenu: NSMenu?
    
    private let cleanExitKey = "lastSessionCleanExit"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        originalMainMenu = NSApp.mainMenu
        
        // Detect if previous session did not exit cleanly (force-quit/crash/kill)
        let wasClean = UserDefaults.standard.bool(forKey: cleanExitKey)
        if wasClean == false {
            let entry = CompletionLogEntry(kidName: "System (previous session ended unexpectedly)", timestamp: Date())
            GatekeeperLogic.shared.completionLog.insert(entry, at: 0)
        }
        UserDefaults.standard.set(false, forKey: cleanExitKey)
        
        if UserDefaults.standard.bool(forKey: "launchAtLoginEnabled") {
            try? SMAppService.mainApp.register()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: cleanExitKey)
    }
    
    func setMenuHidden(_ hidden: Bool) {
        if hidden {
            NSApp.mainMenu = nil
        } else {
            NSApp.mainMenu = originalMainMenu
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if GatekeeperLogic.shared.isAdminAuthenticated {
            return .terminateNow
        } else {
            NSSound.beep()
            return .terminateCancel
        }
    }
    
    // Prevent a stray small window if the user reopens the app while unlocked
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if GatekeeperLogic.shared.isLocked {
            // When locked, ensure our window is frontmost and full screen
            if let window = NSApplication.shared.windows.first {
                if !window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                }
                window.level = .mainMenu + 1
            }
        } else {
            // While unlocked, keep app hidden and do not show a window
            NSApp.hide(nil)
        }
        // Return false to indicate we handled showing/hiding ourselves
        return false
    }
}

@main
struct ChoreLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
