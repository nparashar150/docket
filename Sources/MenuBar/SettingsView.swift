import AppKit
import SwiftUI

/// Docket's Settings window.
///
/// It owns no state: the app passes a binding to the single `PersistedState`
/// it already persists, so every edit here is saved by the same code path that
/// saves everything else.
struct SettingsView: View {
    @Binding var state: PersistedState
    /// Which tab opens first. The menu bar and the Dock's own menu both land
    /// on General; a caller with something specific to show can say so.
    var initialTab: String = "General"
    var onApplyMacOSProfile: () -> Void
    var onCaptureCurrentDock: () -> Void
    /// Sizing the shelf goes through `AppState.setScale`, which also writes
    /// the active profile and records that the size is now the user's. The
    /// slider used to bind straight to the stored value and do neither.
    var onSetScale: (Double) -> Void
    /// Undoing that, and the same for the app list. Both overrides used to be
    /// one directional, with nothing in the app able to clear them.
    var onResumeFollowingScale: () -> Void
    var onResumeMirroringApps: () -> Void
    /// Both present a file panel, which is AppKit's job rather than a view's.
    var onBackUp: () -> Void
    var onRestore: () -> Void
    /// Profile management. Through closures for the same reason as the rest:
    /// this view owns no state and every one of these has to reach AppState,
    /// which also decides what is allowed.
    var onCreateProfile: (ProfileKind) -> Void
    var onRenameProfile: (UUID, String) -> Void
    var onDuplicateProfile: (UUID?) -> Void
    var onDeleteProfile: (UUID?) -> Void

    @State private var tab = "General"

    /// The size the shelf is actually drawn at, which is the Dock's while
    /// following and the stored one once overridden. Showing the stored value
    /// unconditionally meant the readout disagreed with the shelf.
    private var shownScale: Double {
        DockFollowing.scale(overridden: state.customDock.scaleOverridden == true,
                            custom: state.customDock.scale,
                            system: SystemDockSettings.shared.matchedScale,
                            following: state.customDock.followSystemDock)
    }

    /// Both overrides only mean anything while following: with following off,
    /// the shelf's size and app list are the user's by definition and there is
    /// nothing to hand back.
    private var scaleOverridden: Bool {
        state.customDock.followSystemDock && state.customDock.scaleOverridden == true
    }

    private var adoptedApps: Bool {
        state.customDock.followSystemDock && state.customDock.mirrorSystemApps == false
    }


    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "General") { general }
            Tab("Dock", systemImage: "dock.rectangle", value: "Dock") { dock }
            Tab("Widgets", systemImage: "square.grid.2x2", value: "Widgets") { widgets }
            Tab("About", systemImage: "info.circle", value: "About") { about }
        }
        .frame(width: 520, height: 460)
        .onAppear { tab = initialTab }
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section("Appearance") {
                Picker("App appearance", selection: $state.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text(title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Updates") {
                // The consent alert promises this control exists, so it does.
                // Binding through a default of false means a state file that
                // predates the question reads as off rather than as answered.
                Toggle("Check for new versions", isOn: Binding(
                    get: { state.checkForUpdates == true },
                    set: { state.checkForUpdates = $0 }))
                    .help("Once a day, Docket asks GitHub for the latest version number and tells you in its menu bar item if it is newer. Nothing is installed for you, and nothing else is sent.")

                LabeledContent("Version") {
                    Text(UpdateService.shared.current?.description ?? "unknown")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("Dock setup") {
                Picker("", selection: $state.setup) {
                    ForEach(DockSetup.allCases, id: \.self) { setup in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(setup))
                            Text(detail(setup))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(setup)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                LabeledContent("macOS Dock") {
                    HStack {
                        Button("Apply Profile", action: onApplyMacOSProfile)
                            .disabled(state.activeMacOSProfile == nil)
                            .help("Write the selected macOS Dock profile to Apple's Dock.")
                        Button("Capture Current Dock…", action: onCaptureCurrentDock)
                            .help("Save Apple's Dock as it is right now into a new profile.")
                    }
                }
            }

            profiles(.customDock, title: "Shelf profiles",
                     selection: $state.customDock.profileID, allowsNone: false)
            profiles(.macOSDock, title: "macOS Dock profiles",
                     selection: $state.macOSDock.profileID, allowsNone: true)

            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: $state.menuBar.showIcon)
                Picker("Label", selection: $state.menuBar.label) {
                    ForEach(MenuBarLabelMode.allCases, id: \.self) { Text(title($0)).tag($0) }
                }
                .help("Which active profile name is shown next to the menu bar icon.")
            }

            Section {
                HStack {
                    Button("Back Up…", action: onBackUp)
                        .disabled(state.profiles.isEmpty)
                    Button("Restore…", action: onRestore)
                }
            } header: {
                Text("Saved Docks")
            } footer: {
                Text("A backup contains your saved profiles - names, colours, items and widget configuration - not the apps or files they point to. Restoring adds them to what you already have rather than replacing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Profiles

    /// Managing the profiles of one surface.
    ///
    /// None of this was reachable. The model could create, rename, duplicate
    /// and delete a profile, and no control anywhere called any of it, so the
    /// only way to get a second profile was to capture Apple's Dock and the
    /// only name it could ever have was "Current Dock".
    @ViewBuilder
    private func profiles(_ kind: ProfileKind, title: String,
                          selection: Binding<UUID?>, allowsNone: Bool) -> some View {
        let mine = state.profiles(of: kind)
        Section(title) {
            Picker("Active", selection: selection) {
                // "No profile" is the documented "leave the live Dock
                // completely alone" state. It was reachable only until the
                // first capture, after which nothing could return to it.
                if allowsNone { Text("No profile").tag(UUID?.none) }
                ForEach(mine) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .disabled(mine.isEmpty && !allowsNone)

            if let id = selection.wrappedValue, let active = state.profile(id) {
                TextField("Name", text: Binding(
                    get: { active.name },
                    set: { onRenameProfile(id, $0) }))
            }

            HStack {
                Button("New…") { onCreateProfile(kind) }
                Button("Duplicate") { onDuplicateProfile(selection.wrappedValue) }
                    .disabled(selection.wrappedValue == nil)
                Spacer()
                Button("Delete", role: .destructive) {
                    onDeleteProfile(selection.wrappedValue)
                }
                // The shelf has to point at something. Deleting the last one
                // would leave it empty with no way to get a profile back.
                .disabled(selection.wrappedValue == nil
                          || (kind == .customDock && mine.count <= 1))
            }
        }
    }

    // MARK: - Dock

    private var dock: some View {
        Form {
            Section {
                Toggle("Match the macOS Dock", isOn: $state.customDock.followSystemDock)
                    .help("Use the same edge, icon size, magnification and hiding as your real Dock.")
                if state.customDock.followSystemDock {
                    LabeledContent("Currently") {
                        Text(SystemDockSettings.shared.summary)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Turn this off to place and size Docket independently of your Dock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Placement") {
                // .disabled was inside the Picker's content, so it applied to
                // the ForEach and never to the Picker: the control stayed live
                // while following, accepted a choice, and the shelf ignored it.
                Picker("Position", selection: $state.customDock.position) {
                    ForEach(DockPosition.allCases, id: \.self) { Text(title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(state.customDock.followSystemDock)
                .help(state.customDock.followSystemDock
                      ? "While matching the macOS Dock, the shelf takes a free edge beside it."
                      : "Which edge the shelf sits on.")

                Picker("Display", selection: $state.customDock.displayID) {
                    Text("Active display").tag(UInt32?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = screen.docketDisplayID {
                            Text(screen.localizedName).tag(UInt32?.some(id))
                        }
                    }
                }
                .help("The Dock follows the pointer's display unless you pin it to one.")

                LabeledContent("Size") {
                    HStack {
                        // Through setScale, not around it. Binding straight to
                        // the stored value skipped the override flag and never
                        // wrote the profile, so the size silently reverted.
                        Slider(value: Binding(get: { shownScale }, set: onSetScale),
                               in: Geometry.scaleRange)
                        Text("\(Int((shownScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .help("Sizing the shelf yourself stops it matching the Dock's size. Everything else keeps following.")

                // The way back. Choosing a size used to be one directional:
                // the grip set an override that nothing could clear.
                if scaleOverridden {
                    LabeledContent("") {
                        Button("Match the Dock's size", action: onResumeFollowingScale)
                    }
                }
            }

            Section("Material") {
                Picker("Material", selection: $state.customDock.material) {
                    Text("Frosted").tag(DockMaterial.frosted)
                    Text("Liquid Glass").tag(DockMaterial.liquidGlass)
                }
                .pickerStyle(.segmented)

                Picker("Glass style", selection: $state.customDock.glass) {
                    ForEach(GlassStyle.allCases, id: \.self) { Text(title($0)).tag($0) }
                }
                // Disabled rather than hidden so the section does not resize
                // every time the material changes.
                .disabled(state.customDock.material != .liquidGlass)
                .help("Clear is transparent; Regular keeps a tint. Reduce transparency in Accessibility settings overrides both.")
            }

            Section("Behaviour") {
                // Ignored while following, where hiding comes from the Dock's
                // own setting. It used to stay live there and simply have no
                // effect, which reads as a broken toggle rather than one that
                // does not apply.
                Toggle("Automatically hide", isOn: $state.customDock.autoHide)
                    .disabled(state.customDock.followSystemDock)
                    .help(state.customDock.followSystemDock
                          ? "While matching the macOS Dock, the shelf hides when the Dock does."
                          : "Reveal the shelf when the pointer reaches its screen edge.")
                Toggle("Show handle when hidden", isOn: $state.customDock.showHandleWhenHidden)
                    .disabled(!state.customDock.autoHide)
                    .help("A small visible handle while hidden. The edge still reveals the Dock without it.")
                Toggle("Hide when the macOS Dock appears", isOn: $state.customDock.hideWhenMacOSDockAppears)
                    .help("Only matters when both are on the same edge. An auto-hidden Dock and the shelf share a reveal trigger there, so reaching for one uncovers the other.")
                    .help("Gets out of the way when both Docks share a screen edge.")
                Toggle("Use as desktop widget", isOn: $state.customDock.useAsDesktopWidget)
                    .help("Keeps the Dock on the desktop, behind app windows.")
            }

            Section("Contents") {
                Toggle("Show running apps", isOn: $state.customDock.showRunningApps)
                    .help("Include open apps alongside pinned items.")
                Toggle("Show Trash", isOn: $state.customDock.showTrash)

                // Rearranging a mirrored app takes the list over, which is
                // right, but nothing used to give it back: one drag and the
                // shelf stopped tracking the Dock's apps for good.
                if adoptedApps {
                    LabeledContent("Apps") {
                        Button("Mirror the Dock's apps again", action: onResumeMirroringApps)
                    }
                    .help("The shelf is holding its own copy, taken when you first rearranged one. This hands the list back, and drops the copies so nothing appears twice.")
                }
                Toggle("Magnification", isOn: $state.customDock.magnification)
                    .disabled(state.customDock.followSystemDock)
                    .help("Grow icons under the pointer.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Widgets

    private var widgets: some View {
        Form {
            WidgetSettingsSections(state: $state)

            Section {
                Stepper("Focus", value: $state.timer.work, in: 1...180)
                Stepper("Break", value: $state.timer.rest, in: 1...60)
                Stepper("Long break", value: $state.timer.longBreak, in: 1...180)
                Stepper("Sessions before a long break", value: $state.timer.sessions, in: 1...12)
                LabeledContent("Colour") { swatches }
                Toggle("Alerts", isOn: $state.timer.alerts)
                    .help("Notify when a focus session or break ends.")
            } header: {
                Text("Focus Timer")
            } footer: {
                Text("Every Focus Timer widget shares these settings - Docket treats them as one timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var swatches: some View {
        HStack(spacing: 10) {
            ForEach(PaletteColor.picker, id: \.self) { colour in
                Button {
                    state.timer.color = colour
                } label: {
                    Circle()
                        .fill(Color(hex: colour.hex))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(state.timer.color == colour ? 0.7 : 0), lineWidth: 2)
                                .padding(-3)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colour.rawValue.capitalized)
            }
        }
    }

    // MARK: - About

    private var about: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("Docket").font(.title2.weight(.semibold))
                    Text("Version \(shortVersion)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("Docket keeps everything on this Mac, in a single file in Application Support. Nothing is synced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .formStyle(.grouped)
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
}

// MARK: - Labels

private func title(_ value: AppAppearance) -> String {
    switch value {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
}

private func title(_ value: DockSetup) -> String {
    switch value {
    case .macOSDockOnly: "macOS Dock only"
    case .both: "Both"
    case .customReplacement: "Custom Dock replaces the macOS Dock"
    }
}

private func detail(_ value: DockSetup) -> String {
    switch value {
    case .macOSDockOnly: "Save and switch layouts for Apple's Dock. No widgets."
    case .both: "Apple's Dock for apps, a custom Dock beside it for widgets."
    case .customReplacement: "Apps, widgets, folders and links in one Dock. Apple's Dock is auto-hidden."
    }
}

private func title(_ value: DockPosition) -> String {
    switch value {
    case .left: "Left"
    case .bottom: "Bottom"
    case .right: "Right"
    }
}

private func title(_ value: GlassStyle) -> String {
    switch value {
    case .regular: "Regular"
    case .clear: "Clear"
    }
}

private func title(_ value: MenuBarLabelMode) -> String {
    switch value {
    case .none: "No label"
    case .native: "macOS Dock profile"
    case .custom: "Custom Dock profile"
    case .both: "Both profiles"
    }
}

private extension NSScreen {
    /// `CGDirectDisplayID` for this screen, which is what `displayID` stores.
    var docketDisplayID: UInt32? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }
}
