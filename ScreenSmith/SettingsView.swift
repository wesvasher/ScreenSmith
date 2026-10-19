import SwiftUI
import Combine
import ServiceManagement

enum SettingsPage: Hashable {
    case general
    case presets
    case display(CGDirectDisplayID)
}

/// Which page the Settings window shows. Shared with the menu so it can open Settings on a specific page.
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPage? = .general
}

struct SettingsView: View {
    @EnvironmentObject private var manager: DisplayManager
    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Label("Settings", systemImage: "gearshape")
                    .tag(SettingsPage.general)
                Label("Presets", systemImage: "rectangle.stack")
                    .tag(SettingsPage.presets)

                Section("Displays") {
                    ForEach(manager.displays, id: \.self) { displayID in
                        Label {
                            HStack {
                                Text(manager.getDisplayName(for: displayID))
                                if CGDisplayIsMain(displayID) != 0 {
                                    Spacer()
                                    Image(systemName: "menubar.rectangle")
                                        .foregroundStyle(.secondary)
                                        .help("Main display: the menu bar is on this display")
                                        .accessibilityLabel("Main display")
                                }
                            }
                        } icon: {
                            DisplayIconView(emoji: manager.icon(for: displayID), size: 18)
                        }
                        .tag(SettingsPage.display(displayID))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch navigation.selection {
            case .display(let displayID):
                // A fresh view per display so unapplied edits don't carry over between pages.
                DisplaySettingsView(displayID: displayID).id(displayID)
            case .presets:
                PresetsSettingsView()
            default:
                GeneralSettingsView()
            }
        }
        .toolbar(removing: .title)
        .onChange(of: manager.displays) { _, displays in
            if case .display(let displayID) = navigation.selection, !displays.contains(displayID) {
                navigation.selection = .general
            }
        }
    }
}

/// Light or dark mode for the whole app (menu and Settings); Auto follows the system.
enum AppAppearance: String, CaseIterable {
    case auto, light, dark

    static let key = "appearance"

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    func apply() {
        switch self {
        case .auto: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func applyStored() {
        let stored = UserDefaults.standard.string(forKey: key).flatMap { AppAppearance(rawValue: $0) }
        (stored ?? .auto).apply()
    }
}

/// Version details shown at the top of the Settings page.
enum AppInfo {
    static let releasesURL = URL(string: "https://github.com/wesvasher/ScreenSmith/releases/latest")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// When the app was built. Release DMGs are built on release day and copying out of the DMG keeps the date,
    /// so for a downloaded copy this is the release date; for a Debug build it's the last build.
    static var releaseDate: Date? {
        try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static var releaseDateLabel: String {
        #if DEBUG
        "Built"
        #else
        "Released"
        #endif
    }
}

struct GeneralSettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(RefreshFilter.key) private var minimumRefreshRate = 0
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.auto
    /// What the cards show. Kept apart from `appearance` because @AppStorage updates arrive outside the
    /// animation, so the ring wouldn't slide.
    @State private var shownAppearance = AppAppearance.auto
    @Namespace private var appearanceNamespace
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                aboutHeader
            }

            Section("Appearance") {
                HStack(spacing: 10) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        Button {
                            // Switch the app's appearance once the ring has slid over, since redrawing the
                            // whole window mid-animation cuts it short.
                            withAnimation(SelectionCard<EmptyView>.animation) {
                                shownAppearance = option
                            } completion: {
                                appearance = option
                                option.apply()
                            }
                        } label: {
                            SelectionCard(title: option.title, selected: shownAppearance == option,
                                          namespace: appearanceNamespace) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 20))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(shownAppearance == option ? .isSelected : [])
                    }
                }
            }

            Section {
                Picker("Hide refresh rates below", selection: $minimumRefreshRate) {
                    Text("Off").tag(0)
                    Divider()
                    ForEach(RefreshFilter.rates, id: \.self) { rate in
                        Text("\(rate)Hz").tag(rate)
                    }
                }
                Toggle("Start at Login", isOn: Binding(get: { startAtLogin }, set: setLoginItem))
            }

            Section("Updating") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ScreenSmith doesn't update itself. To get the latest version:")
                    Text("1. Download the DMG from the latest release on GitHub.")
                    Text("2. Quit ScreenSmith, then drag the new copy into Applications, replacing the old one.")
                    Text("3. Open it. If macOS blocks it, click Open Anyway in System Settings > Privacy & Security.")
                    Text("Your presets and display names are kept.")
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Open Releases Page") {
                        openURL(AppInfo.releasesURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            startAtLogin = SMAppService.mainApp.status == .enabled
            shownAppearance = appearance
        }
    }

    private var aboutHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("ScreenSmith").font(.title2.weight(.semibold))
                Text("Version \(AppInfo.version)")
                    .foregroundStyle(.secondary)
                if let date = AppInfo.releaseDate {
                    Text("\(AppInfo.releaseDateLabel) \(date.formatted(date: .long, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func setLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            try (enabled ? service.register() : service.unregister())
        } catch {
            NSLog("ScreenSmith: failed to update login item: \(error)")
        }
        // Show what macOS actually did, not what was requested.
        startAtLogin = service.status == .enabled
        if enabled && service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

struct PresetsSettingsView: View {
    @EnvironmentObject private var manager: DisplayManager
    @EnvironmentObject private var store: PresetStore
    @State private var presetToDelete: Preset?
    /// Unapplied edits by preset ID, so this page works like the display pages: nothing saves until Apply.
    @State private var draftNames: [UUID: String] = [:]
    /// Unapplied resolution changes: preset ID → display key → `DisplayMode.id`.
    @State private var draftModes: [UUID: [String: String]] = [:]
    /// Unapplied rotation changes: preset ID → display key → degrees.
    @State private var draftRotations: [UUID: [String: Int]] = [:]

    var body: some View {
        if store.presets.isEmpty {
            ContentUnavailableView("No Presets", systemImage: "rectangle.stack", description:
                Text("Choose Presets › Save preset... in the ScreenSmith menu to save the current resolution of each attached display."))
        } else {
            VStack(spacing: 0) {
                Form {
                    ForEach(store.presets) { preset in
                        Section {
                            // Grouped forms draw text fields borderless, which reads as plain text;
                            // a bordered field and a pencil make it obvious the name is editable.
                            LabeledContent {
                                TextField("Name", text: nameBinding(for: preset), prompt: Text("Untitled Preset"))
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 260)
                                    .onSubmit(applyChanges)
                                    .help("Type a new name, then click Apply Changes")
                            } label: {
                                Label("Name", systemImage: "pencil")
                            }
                            ForEach(preset.displays) { entry in
                                LabeledContent(label(for: entry)) {
                                    if let displayID = manager.connectedDisplay(forKey: entry.displayKey) {
                                        HStack {
                                            ModePicker(displayID: displayID,
                                                       selection: modeBinding(for: preset, entry: entry),
                                                       including: [entry.modeID])
                                            if manager.canRotate(displayID) {
                                                RotationPicker(selection: rotationBinding(for: preset, entry: entry))
                                            }
                                        }
                                    } else {
                                        // Modes can only be listed for attached displays.
                                        Text(entry.summary)
                                    }
                                }
                            }
                            HStack {
                                Spacer()
                                Button("Delete Preset...", role: .destructive) { presetToDelete = preset }
                            }
                        }
                    }
                }
                .formStyle(.grouped)

                Divider()

                HStack {
                    Spacer()
                    Button("Apply Changes", action: applyChanges)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasChanges)
                }
                .padding(12)
            }
            .confirmationDialog("Delete \u{201C}\(presetToDelete?.displayName ?? "")\u{201D}?",
                                isPresented: Binding(get: { presetToDelete != nil }, set: { if !$0 { presetToDelete = nil } }),
                                presenting: presetToDelete) { preset in
                Button("Delete", role: .destructive) {
                    draftNames[preset.id] = nil
                    draftModes[preset.id] = nil
                    draftRotations[preset.id] = nil
                    store.delete(preset)
                }
            } message: { _ in
                Text("This can't be undone.")
            }
        }
    }

    private func nameBinding(for preset: Preset) -> Binding<String> {
        Binding(get: { draftNames[preset.id] ?? preset.name },
                set: { draftNames[preset.id] = $0 })
    }

    private func modeBinding(for preset: Preset, entry: PresetDisplay) -> Binding<String> {
        Binding(get: { draftModes[preset.id]?[entry.displayKey] ?? entry.modeID },
                set: { draftModes[preset.id, default: [:]][entry.displayKey] = $0 })
    }

    /// Presets saved before rotation support have no rotation; show them as Standard.
    private func rotationBinding(for preset: Preset, entry: PresetDisplay) -> Binding<Int> {
        Binding(get: { draftRotations[preset.id]?[entry.displayKey] ?? entry.rotation ?? 0 },
                set: { draftRotations[preset.id, default: [:]][entry.displayKey] = $0 })
    }

    private var hasChanges: Bool {
        store.presets.contains { preset in
            let nameChanged = draftNames[preset.id].map { $0 != preset.name } ?? false
            let displayChanged = preset.displays.contains { entry in
                let modeChanged = draftModes[preset.id]?[entry.displayKey].map { $0 != entry.modeID } ?? false
                let rotationChanged = draftRotations[preset.id]?[entry.displayKey].map { $0 != (entry.rotation ?? 0) } ?? false
                return modeChanged || rotationChanged
            }
            return nameChanged || displayChanged
        }
    }

    private func applyChanges() {
        for index in store.presets.indices {
            let preset = store.presets[index]
            if let draft = draftNames[preset.id] {
                store.presets[index].name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            store.presets[index].displays = preset.displays.map { entry in
                var updated = entry
                if let modeID = draftModes[preset.id]?[entry.displayKey], modeID != entry.modeID,
                   let displayID = manager.connectedDisplay(forKey: entry.displayKey),
                   let mode = manager.getModes(for: displayID).first(where: { $0.id == modeID }) {
                    updated = updated.replacingMode(with: mode)
                }
                if let rotation = draftRotations[preset.id]?[entry.displayKey], rotation != (entry.rotation ?? 0) {
                    updated = updated.replacingRotation(with: rotation)
                }
                return updated
            }
        }
        draftNames = [:]
        draftModes = [:]
        draftRotations = [:]
    }

    /// Uses the display's current name and icon when it's attached, so renames show up here too.
    private func label(for entry: PresetDisplay) -> String {
        guard let displayID = manager.connectedDisplay(forKey: entry.displayKey) else {
            return "\(entry.icon) \(entry.displayName) (not connected)"
        }
        return "\(manager.icon(for: displayID)) \(manager.getDisplayName(for: displayID))"
    }
}

struct DisplaySettingsView: View {
    @EnvironmentObject private var manager: DisplayManager
    let displayID: CGDirectDisplayID

    @State private var nickname = ""
    @State private var mainDisplayFailed = false
    @State private var icon = DisplayIcon.desktop
    /// The fourth, user-changeable choice. Starts as 😀 unless the saved icon is already a custom emoji.
    @State private var customEmoji = DisplayIcon.defaultCustom
    /// What the custom tile's text field holds; normalised back to `customEmoji` after every edit.
    @State private var customFieldText = DisplayIcon.defaultCustom
    @FocusState private var customFieldFocused: Bool
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    section("Display Nickname") {
                        HStack {
                            TextField("Display Nickname", text: $nickname,
                                      prompt: Text(manager.defaultName(for: displayID)))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(apply)
                            Button("Use Suggested Name") {
                                nickname = manager.defaultName(for: displayID)
                            }
                            .disabled(trimmedNickname == manager.defaultName(for: displayID))
                        }
                    }

                    section("Icon Selector") {
                        iconCards
                    }

                    section("Details") {
                        VStack(spacing: 10) {
                            ForEach(manager.details(for: displayID)) { row in
                                HStack {
                                    Text(row.label).foregroundStyle(.secondary)
                                    Spacer()
                                    switch row.kind {
                                    case .currentMode:
                                        ModePicker(displayID: displayID, selection: currentModeSelection)
                                    case .rotation:
                                        RotationPicker(selection: Binding(
                                            get: { manager.rotation(for: displayID) },
                                            set: { manager.setRotation($0, for: displayID) }
                                        ))
                                    case .mainDisplay:
                                        mainDisplayControl
                                    case .text:
                                        Text(row.value).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Apply Changes", action: apply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
            .padding(12)
        }
        .onAppear(perform: load)
        .alert("Couldn't make this the main display", isPresented: $mainDisplayFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("macOS didn't accept the change. You can set the main display in System Settings › Displays › Arrange by dragging the menu bar.")
        }
    }

    private static let customTag = "custom"
    private static let cardIconSize = SelectionCard<EmptyView>.iconSize
    private static let cardPadding = SelectionCard<EmptyView>.padding
    private static let selectionAnimation = SelectionCard<EmptyView>.animation

    /// `icon` as a card tag: built-in emoji are their own tags, anything else is the custom card.
    private var selectedTag: String {
        DisplayIcon.builtIns.contains(icon) ? icon : Self.customTag
    }

    private func select(_ tag: String) {
        // Buttons don't take focus on macOS, so release the emoji field explicitly when leaving Custom.
        if tag != Self.customTag { customFieldFocused = false }
        withAnimation(Self.selectionAnimation) {
            icon = tag == Self.customTag ? customEmoji : tag
        }
    }

    /// Four selectable cards in one row. The custom emoji's instructions only appear while it's selected.
    private var iconCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(DisplayIcon.builtIns, id: \.self) { emoji in
                    Button { select(emoji) } label: {
                        iconCard(tag: emoji, title: DisplayIcon.title(for: emoji)) {
                            DisplayIconView(emoji: emoji, size: Self.cardIconSize)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DisplayIcon.title(for: emoji))
                    .accessibilityAddTraits(selectedTag == emoji ? .isSelected : [])
                }

                // The emoji sits on top of the card's button rather than inside it,
                // because it's a text field that has to receive its own clicks.
                ZStack(alignment: .top) {
                    Button { select(Self.customTag) } label: {
                        iconCard(tag: Self.customTag, title: "Custom") {
                            Color.clear
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Custom emoji")
                    .accessibilityAddTraits(selectedTag == Self.customTag ? .isSelected : [])

                    customEmojiField
                        .padding(.top, Self.cardPadding)
                }
            }

            if selectedTag == Self.customTag {
                Text("To change the custom emoji, [click here](screensmith:emoji), then double-click any emoji in the window that opens.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { _ in
                        openEmojiPicker()
                        return .handled
                    })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func iconCard<Icon: View>(tag: String, title: String, @ViewBuilder icon: () -> Icon) -> some View {
        SelectionCard(title: title, selected: selectedTag == tag, namespace: selectionNamespace, icon: icon)
    }

    /// The custom emoji is a real text field: the system emoji picker types into whichever field has focus.
    private var customEmojiField: some View {
        TextField("Custom emoji", text: $customFieldText)
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: Self.cardIconSize * 0.8))
            .multilineTextAlignment(.center)
            .focused($customFieldFocused)
            .frame(width: Self.cardIconSize, height: Self.cardIconSize)
            // Nearly invisible so its insertion point and selection highlight never show, but still
            // clickable and still the target for the emoji picker. The emoji itself is drawn on top.
            .opacity(0.02)
            .overlay {
                DisplayIconView(emoji: customEmoji, size: Self.cardIconSize)
                    .allowsHitTesting(false)
            }
            .help("Custom emoji")
            .onChange(of: customFieldFocused) { _, focused in
                if focused { select(Self.customTag) }
            }
            .onChange(of: customFieldText) { _, text in
                // The new emoji may be inserted before or after the old one, so take the first one that differs.
                let emoji = text.filter(\.isEmoji).map(String.init)
                if let picked = emoji.first(where: { $0 != customEmoji }) {
                    customEmoji = picked
                    select(Self.customTag)
                    customFieldFocused = false
                }
                if customFieldText != customEmoji { customFieldText = customEmoji }
            }
    }

    private func openEmojiPicker() {
        select(Self.customTag)
        customFieldFocused = true
        // Give the field a moment to become first responder, since the picker types into it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }

    /// Switches resolution as soon as a mode is picked, like the menu bar menu; Apply Changes is only for
    /// the nickname and icon, so Current Mode always shows what the display is really using.
    private var currentModeSelection: Binding<String> {
        Binding(
            get: { manager.getCurrentMode(for: displayID)?.id ?? "" },
            set: { id in
                if let mode = manager.getModes(for: displayID).first(where: { $0.id == id }) {
                    manager.setResolution(displayID: displayID, mode: mode.mode)
                }
            }
        )
    }

    @ViewBuilder
    private var mainDisplayControl: some View {
        if CGDisplayIsMain(displayID) != 0 {
            Label("Yes, the menu bar is here", systemImage: "menubar.rectangle")
        } else {
            Button("Move Menu Bar to This Display") {
                if !manager.makeMainDisplay(displayID) { mainDisplayFailed = true }
            }
            .disabled(manager.isMirroring(displayID))
            .help(manager.isMirroring(displayID)
                  ? "This display is mirroring another display, so it can't be the main display on its own."
                  : "Makes this the main display. The menu bar moves here, and the Dock too unless you've moved it.")
        }
    }

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedNickname != (manager.customName(for: displayID) ?? "") || icon != manager.icon(for: displayID)
    }

    private func load() {
        nickname = manager.customName(for: displayID) ?? ""
        icon = manager.icon(for: displayID)
        customEmoji = DisplayIcon.builtIns.contains(icon) ? DisplayIcon.defaultCustom : icon
        customFieldText = customEmoji
    }

    private func apply() {
        // An empty nickname goes back to the default name.
        if trimmedNickname.isEmpty {
            manager.resetName(for: displayID)
        } else {
            manager.saveCustomName(trimmedNickname, for: displayID)
        }
        nickname = trimmedNickname
        manager.setIcon(icon, for: displayID)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// A selectable card with an icon over a title, as in the icon and appearance selectors. Cards sharing a
/// namespace pass one accent ring between them as the selection changes.
struct SelectionCard<Icon: View>: View {
    static var iconSize: CGFloat { 26 }
    static var padding: CGFloat { 10 }
    static var animation: Animation { .snappy(duration: 0.25) }

    let title: String
    let selected: Bool
    let namespace: Namespace.ID
    let icon: Icon

    init(title: String, selected: Bool, namespace: Namespace.ID, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.selected = selected
        self.namespace = namespace
        self.icon = icon()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 4) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
            Text(title)
                .font(.callout)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Self.padding)
        .background(shape.fill(selected ? AnyShapeStyle(.background) : AnyShapeStyle(.quinary)))
        .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        .overlay {
            // One accent ring that slides between cards as the selection changes.
            if selected {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(5)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .contentShape(shape)
    }
}

/// A popup of a display's resolutions, grouped like the menu (Retina/Standard, split by notch when relevant),
/// with the same density icons and Native tags. Modes below the refresh cutoff are left out unless the
/// selection or `including` needs them.
struct ModePicker: View {
    @EnvironmentObject private var manager: DisplayManager
    @AppStorage(RefreshFilter.key) private var minimumRefreshRate = 0
    let displayID: CGDirectDisplayID
    @Binding var selection: String
    var including: Set<String> = []

    var body: some View {
        let nativeSize = manager.nativePixelSize(for: displayID)
        Picker("Resolution", selection: $selection) {
            ForEach(manager.modeGroups(for: displayID, minimumRefreshRate: minimumRefreshRate,
                                       including: including.union([selection]))) { group in
                Section(group.title) {
                    ForEach(group.modes) { mode in
                        Label(mode.menuLabel(nativeSize: nativeSize), image: mode.iconName)
                            .labelStyle(.titleAndIcon)
                            .tag(mode.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

struct RotationPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("Rotation", selection: $selection) {
            ForEach(DisplayRotation.options, id: \.self) { degrees in
                Text(DisplayRotation.title(for: degrees)).tag(degrees)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

struct DisplayIconView: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.8))
            .frame(width: size, height: size)
    }
}
