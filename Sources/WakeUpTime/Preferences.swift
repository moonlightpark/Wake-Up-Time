import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Builds the General / Sounds / Clocks preferences window with a toolbar-style tab bar.
enum PreferencesWindow {
    static func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(item(GeneralPane(), "General", "switch.2"))
        tabs.addTabViewItem(item(SoundsPane(), "Sounds", "music.note"))
        tabs.addTabViewItem(item(ClocksPane(), "Clocks", "clock"))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static func item<V: View>(_ view: V, _ label: String, _ symbol: String) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

struct GeneralPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Adjust system volume", isOn: $settings.adjustSystemVolume)
            Text("Automatically adjusts system volume before the alarm\nand restores it afterwards to the original level.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
                .padding(.top, -6)
            Toggle("24-hour display", isOn: $settings.use24Hour)
            Toggle("Flash the time separators", isOn: $settings.flashSeparators)
            Toggle("Keep above other windows", isOn: $settings.keepOnTop)
            Toggle("Keep Mac awake while the alarm is set", isOn: $settings.keepAwake)
            Text("Without this, your Mac may go to sleep on its own and miss the alarm.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
                .padding(.top, -6)

            HStack {
                Text("Snooze time:")
                Slider(value: Binding(get: { Double(settings.snoozeMinutes) },
                                      set: { settings.snoozeMinutes = Int($0.rounded()) }),
                       in: 1...20, step: 1)
                    .frame(width: 150)
                Text("\(settings.snoozeMinutes) minutes")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .leading)
            }
            .padding(.top, 4)

            Divider().padding(.vertical, 6)

            HStack {
                Text("Reset all dialog warnings:")
                Button("Reset Warnings") { settings.resetWarnings() }
            }
            .frame(maxWidth: .infinity)
        }
        .toggleStyle(.checkbox)
        .padding(24)
        .frame(width: 460)
    }
}

struct SoundsPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var library = SoundLibrary.shared
    @ObservedObject private var preview = SoundPlayer.preview
    @State private var selection: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            Table(library.items, selection: $selection) {
                TableColumn("Hide") { item in
                    Toggle("", isOn: hiddenBinding(item.id))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
                .width(36)
                TableColumn("Name") { item in
                    if item.kind == .custom {
                        TextField("", text: titleBinding(item))
                            .textFieldStyle(.plain)
                            .foregroundStyle(item.isAvailable ? .primary : .secondary)
                    } else {
                        Text(item.title)
                    }
                }
                TableColumn("Type") { item in
                    Text(item.isAvailable ? item.kind.rawValue : "Missing")
                        .foregroundStyle(item.isAvailable ? Color.secondary : Color.orange)
                }
                .width(70)
            }
            .dropDestination(for: URL.self) { urls, _ in
                add(urls)
                return true
            }
            .frame(height: 300)

            Text("Hidden sounds are left out of the drawer's list. Drag audio files here to add them;\nclick a custom sound's name to rename it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                ControlGroup {
                    Button(action: openPanel) { Image(systemName: "plus") }
                    Button(action: removeSelected) { Image(systemName: "minus") }
                        .disabled(library.item(id: selection ?? "")?.kind != .custom)
                }
                .frame(width: 60)
                Spacer()
                Button(action: togglePreview) {
                    Image(systemName: preview.playingID == nil ? "play.fill" : "stop.fill")
                        .frame(width: 20)
                }
                .disabled(selection == nil && preview.playingID == nil)
                Spacer()
                Color.clear.frame(width: 60, height: 1)
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert("Unsupported audio format", isPresented: Binding(get: { errorMessage != nil },
                                                              set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func hiddenBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.hiddenSoundIDs.contains(id) },
                set: { hide in
                    if hide { settings.hiddenSoundIDs.insert(id) } else { settings.hiddenSoundIDs.remove(id) }
                })
    }

    private func titleBinding(_ item: SoundItem) -> Binding<String> {
        Binding(get: { library.item(id: item.id)?.title ?? item.title },
                set: { library.rename(id: item.id, to: $0) })
    }

    private func add(_ urls: [URL]) {
        var failed: [String] = []
        for url in urls {
            do { try library.addCustom(url) } catch { failed.append(url.lastPathComponent) }
        }
        if !failed.isEmpty {
            errorMessage = "These files can't be used as alarm sounds:\n" + failed.joined(separator: "\n")
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.message = "Choose sounds to add to Wake Up Time"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func removeSelected() {
        guard let id = selection else { return }
        if preview.playingID == id { preview.stop() }
        library.removeCustom(id: id)
        selection = nil
    }

    private func togglePreview() {
        if preview.playingID != nil {
            preview.stop()
        } else if let id = selection, let item = library.item(id: id) {
            do {
                try preview.play(item, volume: Float(settings.volume), loop: false)
            } catch {
                errorMessage = "The selected sound is not available at the original location."
            }
        }
    }
}

struct ClocksPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var alarm = AlarmController.shared

    var body: some View {
        let style = ClockStyle(rawValue: settings.clockStyle) ?? .digital
        VStack(alignment: .leading, spacing: 10) {
            Text("Full Screen Clocks").font(.headline)
            HStack(alignment: .top, spacing: 14) {
                List(ClockStyle.allCases, selection: Binding(get: { style },
                                                             set: { if let s = $0 { settings.clockStyle = s.rawValue } })) { s in
                    Text(s.title).tag(s)
                }
                .frame(width: 160)
                ClockFace(style: style, date: alarm.now, use24Hour: TimeFormat.uses24Hour(settings),
                          colonVisible: alarm.colonVisible)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 280)
            HStack {
                Spacer()
                Button("Show Full Screen Clock") {
                    NSApp.sendAction(#selector(AppDelegate.toggleFullScreenClock(_:)), to: nil, from: nil)
                }
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}
