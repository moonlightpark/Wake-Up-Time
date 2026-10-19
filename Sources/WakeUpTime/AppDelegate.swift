import AppKit
import Combine
import SwiftUI

/// Borderless main window that can still become key (for keyboard snooze and the date picker).
final class MainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings = Settings.shared
    private let alarm = AlarmController.shared
    private var mainWindow: MainWindow!
    private var preferencesWindow: NSWindow?
    private var fullScreenWindow: FullScreenClockWindow?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        createMainWindow()

        settings.$keepOnTop
            .sink { [weak self] onTop in self?.mainWindow.level = onTop ? .floating : .normal }
            .store(in: &cancellables)
        settings.$drawerOpen
            .dropFirst()
            .sink { [weak self] open in self?.resizeForDrawer(open: open, animate: true) }
            .store(in: &cancellables)
        Publishers.CombineLatest(alarm.$phase, settings.$keepAwake)
            .sink { phase, keepAwake in Power.keepSystemAwake(phase != .off && keepAwake) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .alarmDidStartRinging)
            .sink { [weak self] _ in self?.alarmStarted() }
            .store(in: &cancellables)

        // Any key snoozes while ringing; ESC leaves the full screen clock.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let inClockWindow = event.window === self.mainWindow || event.window === self.fullScreenWindow
            if event.keyCode == 53, event.window === self.fullScreenWindow {
                self.closeFullScreenClock()
                return nil
            }
            if self.alarm.phase == .ringing, inClockWindow, !event.modifierFlags.contains(.command) {
                self.alarm.snooze()
                return nil
            }
            // With a non-Latin input source (e.g. Korean) ⌘D arrives as "⌘ㄷ" and matches no
            // menu item; retry the shortcut with the key's character on the ASCII-capable layout.
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers, !chars.isEmpty, !chars.allSatisfy(\.isASCII),
               let base = KeyboardLayout.asciiCharacter(for: event.keyCode),
               case let ascii = event.modifierFlags.contains(.shift) ? base.uppercased() : base,
               let translated = NSEvent.keyEvent(with: .keyDown, location: event.locationInWindow,
                                                 modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                                                 windowNumber: event.windowNumber, context: nil,
                                                 characters: ascii, charactersIgnoringModifiers: ascii,
                                                 isARepeat: event.isARepeat, keyCode: event.keyCode),
               NSApp.mainMenu?.performKeyEquivalent(with: translated) == true {
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard alarm.phase != .off, !settings.suppressQuitWarning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Wake Up Time?"
        alert.informativeText = "The alarm is set. If you quit, it will not ring."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { settings.suppressQuitWarning = true }
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        alarm.shutdown()
        Power.keepSystemAwake(false)
        Power.keepDisplayAwake(false)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: alarm.phase == .off ? "Enable Alarm" : "Disable Alarm",
                     action: #selector(toggleAlarm(_:)), keyEquivalent: "")
        return menu
    }

    // MARK: Main window

    private func createMainWindow() {
        let root = MainView(
            onToggleDrawer: { [weak self] in self?.toggleDrawer(nil) },
            onFullScreen: { [weak self] in self?.toggleFullScreenClock(nil) },
            onSleep: { [weak self] in self?.sleepUntilAlarm() })
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []

        let width = settings.drawerOpen ? Layout.openWidth : Layout.closedWidth
        let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: Layout.height),
                                styleMask: [.borderless, .miniaturizable],
                                backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.title = "Wake Up Time"
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("MainWindow")
        mainWindow = window
        resizeForDrawer(open: settings.drawerOpen, animate: false)
        window.makeKeyAndOrderFront(nil)
    }

    private func resizeForDrawer(open: Bool, animate: Bool) {
        var frame = mainWindow.frame
        frame.size = NSSize(width: open ? Layout.openWidth : Layout.closedWidth, height: Layout.height)
        mainWindow.setFrame(frame, display: true, animate: animate)
        mainWindow.invalidateShadow()
    }

    private func alarmStarted() {
        if fullScreenWindow != nil { return }
        NSApp.activate(ignoringOtherApps: true)
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func sleepUntilAlarm() {
        if !settings.suppressSleepWarning {
            let alert = NSAlert()
            alert.messageText = "Sleep until the alarm"
            alert.informativeText = """
                Wake Up Time turns off the display and keeps your Mac awake so the alarm rings on time. \
                Move the mouse or press any key to turn the display back on.

                On a portable Mac, keep the lid open: when the lid is closed, \
                your Mac cannot wake up on its own.
                """
            alert.addButton(withTitle: "Sleep")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            let response = alert.runModal()
            if alert.suppressionButton?.state == .on { settings.suppressSleepWarning = true }
            guard response == .alertFirstButtonReturn else { return }
        }
        Power.sleepDisplay()
    }

    // MARK: Actions

    @objc func showMainWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    @objc func closeWindow(_ sender: Any?) {
        guard let key = NSApp.keyWindow else { return }
        if key === mainWindow {
            mainWindow.orderOut(nil)
        } else if key === fullScreenWindow {
            closeFullScreenClock()
        } else {
            key.performClose(sender)
        }
    }

    @objc func minimizeWindow(_ sender: Any?) {
        NSApp.keyWindow?.miniaturize(sender)
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWindow == nil { preferencesWindow = PreferencesWindow.make() }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleDrawer(_ sender: Any?) {
        settings.drawerOpen.toggle()
    }

    @objc func toggleFullScreenClock(_ sender: Any?) {
        if fullScreenWindow != nil {
            closeFullScreenClock()
            return
        }
        guard let screen = mainWindow.screen ?? NSScreen.main else { return }
        let window = FullScreenClockWindow(screen: screen) { [weak self] in self?.closeFullScreenClock() }
        fullScreenWindow = window
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSCursor.setHiddenUntilMouseMoves(true)
        Power.keepDisplayAwake(true)
    }

    private func closeFullScreenClock() {
        fullScreenWindow?.orderOut(nil)
        fullScreenWindow = nil
        NSApp.presentationOptions = []
        Power.keepDisplayAwake(false)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    @objc func toggleAlarm(_ sender: Any?) {
        settings.alarmEnabled.toggle()
    }

    @objc func snoozeAlarm(_ sender: Any?) {
        alarm.snooze()
    }

    @objc func stopAlarm(_ sender: Any?) {
        alarm.stop()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleAlarm(_:)):
            item.title = alarm.phase == .off ? "Enable Alarm" : "Disable Alarm"
        case #selector(snoozeAlarm(_:)):
            return alarm.phase == .ringing
        case #selector(stopAlarm(_:)):
            return alarm.phase == .ringing || alarm.phase == .snoozing
        case #selector(toggleDrawer(_:)):
            item.title = settings.drawerOpen ? "Close Drawer" : "Open Drawer"
        case #selector(toggleFullScreenClock(_:)):
            item.title = fullScreenWindow == nil ? "Full Screen Clock" : "Exit Full Screen Clock"
        default:
            break
        }
        return true
    }

    // MARK: Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Wake Up Time")
        app.addItem(withTitle: "About Wake Up Time",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        add(app, "Settings…", #selector(showPreferences(_:)), ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Wake Up Time", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Wake Up Time", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = submenu(main, "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let alarmMenu = submenu(main, "Alarm")
        add(alarmMenu, "Enable Alarm", #selector(toggleAlarm(_:)), "e")
        add(alarmMenu, "Snooze", #selector(snoozeAlarm(_:)), "")
        add(alarmMenu, "Stop Alarm", #selector(stopAlarm(_:)), ".")

        let view = submenu(main, "View")
        add(view, "Flip Drawer", #selector(toggleDrawer(_:)), "d")
        let full = add(view, "Full Screen Clock", #selector(toggleFullScreenClock(_:)), "f")
        full.keyEquivalentModifierMask = [.command, .control]

        let window = submenu(main, "Window")
        add(window, "Minimize", #selector(minimizeWindow(_:)), "m")
        add(window, "Close", #selector(closeWindow(_:)), "w")
        window.addItem(.separator())
        add(window, "Wake Up Time", #selector(showMainWindow(_:)), "1")
        NSApp.windowsMenu = window

        return main
    }

    private func submenu(_ parent: NSMenu, _ title: String) -> NSMenu {
        let item = parent.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
