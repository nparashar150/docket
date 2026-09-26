import AppKit
import SwiftUI

/// The menu bar item: the app's only persistent UI.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let app: AppState
    var onShelfSettingsChanged: (() -> Void)?

    init(app: AppState) {
        self.app = app
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()
    }

    func refreshButton() {
        // The toggle was read by nothing: the status item was always created
        // and always shown. Honoured now, but never to the point of leaving
        // the app unreachable - see `canHideStatusItem`.
        statusItem.isVisible = app.state.menuBar.showIcon || !canHideStatusItem

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled",
                               accessibilityDescription: "Docket")
        button.image?.isTemplate = true
        button.title = labelText.isEmpty ? "" : " \(labelText)"
    }

    /// Whether there is another way into the app if the icon goes.
    ///
    /// Docket is an accessory app: no Dock tile, no window of its own. With
    /// the shelf on screen its context menu reaches Settings, so hiding the
    /// icon is recoverable. Without a shelf it is the only way in, and hiding
    /// it would strand someone in an app they can see no part of and cannot
    /// quit.
    var canHideStatusItem: Bool { app.state.setup != .macOSDockOnly }

    private var labelText: String {
        let native = app.macOSProfile?.name ?? ""
        let custom = app.customProfile?.name ?? ""
        return switch app.state.menuBar.label {
        case .none: ""
        case .native: native
        case .custom: custom
        case .both: [native, custom].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let error = app.lastError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        addProfileSection(to: menu, kind: .customDock, title: "Custom Dock")
        addProfileSection(to: menu, kind: .macOSDock, title: "macOS Dock")

        menu.addItem(.separator())
        menu.addItem(item("Capture Current Dock…", #selector(captureDock)))
        if app.state.originalMacOSDock != nil {
            menu.addItem(item("Restore Original Dock", #selector(restoreDock)))
        }
        menu.addItem(.separator())
        // Only when there is one. An always-present "you are up to date" line
        // is a permanent reminder of something nobody needs reminding of.
        if let update = UpdateService.shared.available {
            let entry = item("Update to \(update.version)…", #selector(openUpdate))
            entry.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                  accessibilityDescription: nil)
            menu.addItem(entry)
            menu.addItem(.separator())
        }
        menu.addItem(item("Add Widget…", #selector(openLibrary)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Docket", #selector(quit), key: "q"))
    }

    @objc private func openUpdate() { UpdateService.shared.openReleasePage() }

    private func addProfileSection(to menu: NSMenu, kind: ProfileKind, title: String) {
        let profiles = app.profiles(of: kind)
        guard !profiles.isEmpty else { return }

        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let activeID = kind == .customDock ? app.state.customDock.profileID : app.state.macOSDock.profileID
        for profile in profiles {
            let entry = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = profile.id
            entry.state = profile.id == activeID ? .on : .off
            entry.image = swatch(profile.color)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
    }

    private func swatch(_ color: PaletteColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(Color(hex: color.hex)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let profile = app.state.profile(id) else { return }
        app.select(profile)
        refreshButton()
        onShelfSettingsChanged?()
        if profile.kind == .macOSDock {
            Task { await app.applyMacOSProfile() }
        }
    }

    @objc private func captureDock() {
        Task {
            await app.captureCurrentDock(named: "Current Dock")
            refreshButton()
        }
    }

    @objc private func restoreDock() {
        Task { await app.restoreOriginalDock() }
    }

    @objc private func openLibrary() {
        LibraryWindow.shared.show(app: app)
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(app: app)
    }

    @objc private func quit() {
        app.saveNow()
        NSApp.terminate(nil)
    }
}
