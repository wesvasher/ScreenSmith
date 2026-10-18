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
                            Text(manager.getDisplayName(for: displayID))
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

struct GeneralSettingsView: View {
    @AppStorage(RefreshFilter.key) private var minimumRefreshRate = 0
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("Hide refresh rates below", selection: $minimumRefreshRate) {
                Text("Off").tag(0)
                Divider()
                ForEach(RefreshFilter.rates, id: \.self) { rate in
                    Text("\(rate)Hz").tag(rate)
                }
            }
            Toggle("Start at Login", isOn: Binding(get: { startAtLogin }, set: setLoginItem))
        }
        .formStyle(.grouped)
        .onAppear { startAtLogin = SMAppService.mainApp.status == .enabled }
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
    /// Unapplied name edits by preset ID, so renames work like the display pages: nothing saves until Apply.
    @State private var draftNames: [UUID: String] = [:]

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
                                    .onSubmit(applyNames)
                                    .help("Type a new name, then click Apply Changes")
                            } label: {
                                Label("Name", systemImage: "pencil")
                            }
                            ForEach(preset.displays) { entry in
                                LabeledContent(label(for: entry)) {
                                    Text(entry.modeDescription)
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
                    Button("Apply Changes", action: applyNames)
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

    private var hasChanges: Bool {
        store.presets.contains { preset in
            draftNames[preset.id].map { $0 != preset.name } ?? false
        }
    }

    private func applyNames() {
        for index in store.presets.indices {
            if let draft = draftNames[store.presets[index].id] {
                store.presets[index].name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        draftNames = [:]
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
                        TextField("Display Nickname", text: $nickname,
                                  prompt: Text(manager.defaultName(for: displayID)))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(apply)
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
                                    Text(row.value).textSelection(.enabled)
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
    }

    private static let customTag = "custom"
    private static let cardIconSize: CGFloat = 26
    private static let cardPadding: CGFloat = 10
    private static let selectionAnimation = Animation.snappy(duration: 0.25)

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
        let selected = selectedTag == tag
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 4) {
            icon()
                .frame(width: Self.cardIconSize, height: Self.cardIconSize)
            Text(title)
                .font(.callout)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Self.cardPadding)
        .background(shape.fill(selected ? AnyShapeStyle(.background) : AnyShapeStyle(.quinary)))
        .overlay(shape.strokeBorder(.separator, lineWidth: 1))
        .overlay {
            // One accent ring that slides between cards as the selection changes.
            if selected {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
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

struct DisplayIconView: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.8))
            .frame(width: size, height: size)
    }
}
