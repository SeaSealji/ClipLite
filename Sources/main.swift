import AppKit
import Carbon

private let appID = "com.local.cliplite2"
private let appName = "ClipLite2"
private let maxHistoryCount = 50
private let historyTTL: TimeInterval = 6 * 60 * 60
private let clipboardPollInterval: TimeInterval = 1.0
private let delayedSaveInterval: TimeInterval = 1.5
private let maxImageBytes = 5 * 1024 * 1024

final class AppLog {
    static let shared = AppLog()

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("run.log")
    }

    func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}

enum ClipboardPayload: Codable, Equatable {
    case text(String)
    case image(Data)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum PayloadType: String, Codable {
        case text
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .image:
            self = .image(try container.decode(Data.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(PayloadType.text, forKey: .type)
            try container.encode(text, forKey: .value)
        case .image(let data):
            try container.encode(PayloadType.image, forKey: .type)
            try container.encode(data, forKey: .value)
        }
    }
}

struct HistoryItem: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let payload: ClipboardPayload

    var title: String {
        switch payload {
        case .text(let text):
            let singleLine = text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return singleLine.isEmpty ? "(empty text)" : String(singleLine.prefix(120))
        case .image(let data):
            return "Image (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        }
    }

    var searchableText: String {
        switch payload {
        case .text(let text):
            return text
        case .image:
            return "image 图片"
        }
    }
}

final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    private let fileURL: URL
    private var saveTimer: Timer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.json")
        load()
        pruneAndSave()
    }

    func add(_ payload: ClipboardPayload) {
        if items.first?.payload == payload {
            return
        }
        items.removeAll { $0.payload == payload }
        items.insert(HistoryItem(id: UUID(), createdAt: Date(), payload: payload), at: 0)
        prune()
        scheduleSave()
    }

    func pruneAndSave() {
        prune()
        save()
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        pruneAndSave()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-historyTTL)
        items = Array(items.filter { $0.createdAt >= cutoff }.prefix(maxHistoryCount))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            items = []
            return
        }
        items = (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: delayedSaveInterval, repeats: false) { [weak self] _ in
            self?.save()
        }
    }
}

final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private let store: HistoryStore
    private var changeCount: Int
    private var timer: Timer?
    private var suppressNextChange = false

    init(store: HistoryStore) {
        self.store = store
        changeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: clipboardPollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func ignoreNextChange() {
        suppressNextChange = true
    }

    private func poll() {
        guard pasteboard.changeCount != changeCount else {
            return
        }
        changeCount = pasteboard.changeCount

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        if let text = pasteboard.string(forType: .string) {
            store.add(.text(text))
            return
        }

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            guard data.count <= maxImageBytes else {
                AppLog.shared.write("skip_large_image bytes=\(data.count) max=\(maxImageBytes)")
                return
            }
            store.add(.image(data))
        }
    }
}

final class HotKeyCenter {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.id == 1 {
                    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                    center.onTrigger()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        guard installStatus == noErr else {
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x434c4950), id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_V)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }
}

final class ClickSelectTableView: NSTableView {
    var onSingleClickRow: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow >= 0 {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            onSingleClickRow?(clickedRow)
            return
        }
        super.mouseDown(with: event)
    }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let store: HistoryStore
    private let onSelect: (HistoryItem) -> Void
    private let tableView = ClickSelectTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Clipboard history is empty")
    private var visibleItems: [HistoryItem] = []

    init(store: HistoryStore, onSelect: @escaping (HistoryItem) -> Void) {
        self.store = store
        self.onSelect = onSelect

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.title = "ClipLite"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildUI()
        reload()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        reload()
        AppLog.shared.write("window_show item_count=\(visibleItems.count)")
        guard let window else { return }
        AppLog.shared.write("window_class=\(String(describing: type(of: window))) visible_before=\(window.isVisible)")
        let rowCount = max(1, min(visibleItems.count, 8))
        window.setContentSize(NSSize(width: 520, height: CGFloat(rowCount * 42 + 16)))
        if let screenFrame = NSScreen.main?.visibleFrame {
            let frame = window.frame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.maxY - frame.height - 90
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        AppLog.shared.write("window_visible_after=\(window.isVisible) key=\(window.isKeyWindow)")
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.title = "History"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 42
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onSingleClickRow = { [weak self] row in
            self?.select(row: row)
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == kVK_Return {
                self.selectCurrentRow()
                return nil
            }
            if event.keyCode == kVK_Escape {
                self.window?.orderOut(nil)
                return nil
            }
            return event
        }
    }

    private func reload() {
        store.pruneAndSave()
        visibleItems = store.items
        tableView.reloadData()
        emptyLabel.isHidden = !visibleItems.isEmpty
        scrollView.isHidden = visibleItems.isEmpty
        if !visibleItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let item = visibleItems[row]
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.lineBreakMode = .byTruncatingTail
        cell.font = .systemFont(ofSize: 13)
        cell.stringValue = item.title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {}

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        true
    }

    @objc private func selectCurrentRow() {
        let row = tableView.selectedRow
        select(row: row)
    }

    private func select(row: Int) {
        AppLog.shared.write("select_row=\(row) visible_count=\(visibleItems.count)")
        guard row >= 0, row < visibleItems.count else {
            if let first = visibleItems.first {
                onSelect(first)
                window?.orderOut(nil)
            }
            return
        }
        onSelect(visibleItems[row])
        window?.orderOut(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HistoryStore()
    private lazy var watcher = ClipboardWatcher(store: store)
    private var statusItem: NSStatusItem?
    private var hotKeyCenter: HotKeyCenter?
    private var historyWindowController: HistoryWindowController?
    private var appToPasteInto: NSRunningApplication?
    private var hotKeyOK = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else {
            AppLog.shared.write("another instance is already running; terminating current instance")
            NSApp.terminate(nil)
            return
        }

        AppLog.shared.write("started bundle=\(Bundle.main.bundleIdentifier ?? "unknown") path=\(Bundle.main.bundlePath)")
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        watcher.start()
        installStatusItem()
        historyWindowController = HistoryWindowController(store: store) { [weak self] item in
            self?.paste(item)
        }
        hotKeyCenter = HotKeyCenter { [weak self] in
            self?.toggleHistoryWindow()
        }
        hotKeyOK = hotKeyCenter?.register() == true
        AppLog.shared.write("hotkey_registered=\(hotKeyOK)")
        rebuildMenu()
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.showHistory()
        }
    }

    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains {
            $0.processIdentifier != currentPID
        }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "CL"
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)

        let showItem = NSMenuItem(title: "Show Clipboard History", action: #selector(showHistory), keyEquivalent: "v")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        appMenu.addItem(showItem)

        let openSettingsItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        openSettingsItem.target = self
        appMenu.addItem(openSettingsItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ClipLite", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Clipboard History", action: #selector(showHistory), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: hotKeyOK ? "Shortcut: ⌘⇧V" : "Shortcut unavailable: ⌘⇧V", action: nil, keyEquivalent: ""))
        let accessibilityItem = NSMenuItem(title: accessibilityTrusted() ? "Accessibility: Granted" : "Accessibility: Not Granted", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit ClipLite", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func showHistory() {
        AppLog.shared.write("show_history menu")
        rememberPasteTarget()
        historyWindowController?.show()
    }

    private func toggleHistoryWindow() {
        if historyWindowController?.window?.isVisible == true {
            AppLog.shared.write("hide_history hotkey")
            historyWindowController?.window?.orderOut(nil)
        } else {
            AppLog.shared.write("show_history hotkey")
            rememberPasteTarget()
            historyWindowController?.show()
        }
    }

    private func rememberPasteTarget() {
        let activeApp = NSWorkspace.shared.frontmostApplication
        if activeApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            appToPasteInto = activeApp
            AppLog.shared.write("paste_target=\(activeApp?.localizedName ?? "unknown") bundle=\(activeApp?.bundleIdentifier ?? "unknown")")
        }
    }

    private func paste(_ item: HistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.payload {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        }
        watcher.ignoreNextChange()
        historyWindowController?.window?.orderOut(nil)

        guard accessibilityTrusted(prompt: true) else {
            AppLog.shared.write("accessibility_missing copied_only")
            showCopiedOnlyAlert()
            rebuildMenu()
            return
        }

        let target = appToPasteInto
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let target {
                AppLog.shared.write("activate_paste_target=\(target.localizedName ?? "unknown")")
                target.activate(options: [.activateIgnoringOtherApps])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            AppLog.shared.write("send_paste_command")
            self.sendPasteCommand()
        }
    }

    private func sendPasteCommand() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func accessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Needed"
        alert.informativeText = "ClipLite needs Accessibility permission to paste into the current focused input. Enable it in System Settings, then try again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func showCopiedOnlyAlert() {
        let alert = NSAlert()
        alert.messageText = "Copied to Clipboard"
        alert.informativeText = "ClipLite does not have Accessibility permission yet, so it copied the item to the clipboard. Press Command-V manually, or grant Accessibility permission to /Applications/ClipLite2.app for automatic paste."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistory()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
