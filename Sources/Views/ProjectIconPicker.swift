// ABOUTME: Project icon and emoji picker views and catalog.
// ABOUTME: Supports preset emojis, SF Symbols, custom inputs, and system character palette.

import SwiftUI

enum ProjectIconCatalog {
    static let quickPicks: [String] = [
        "🚀", "⚡️", "📦", "🛠️", "🌐", "📱", "💻", "🐳",
        "🤖", "🧠", "🎨", "🎮", "🧪", "📚", "💡", "⭐️",
    ]

    static let emojis: [String] = [
        "🚀", "⚡️", "📦", "🛠️", "🌐", "📱", "💻", "🐳",
        "🤖", "🧠", "⚙️", "🔍", "📝", "🔒", "📊", "🏗️",
        "🎨", "🎮", "🧪", "📚", "💡", "⭐️", "🔥", "🚢",
        "🎯", "💎", "☕️", "🍎", "🐧", "🦀", "🐍", "👾",
        "🦄", "🌈", "🍀", "🔑", "💬", "📡", "🔋", "✨",
    ]

    static let symbols: [String] = [
        "folder.fill", "cube.fill", "cpu.fill", "globe",
        "terminal.fill", "sparkles", "hammer.fill", "gearshape.fill",
        "tag.fill", "server.rack", "laptopcomputer", "externaldrive.fill",
        "puzzlepiece.fill", "bolt.fill", "flame.fill", "shield.fill",
        "wand.and.stars", "wrench.and.screwdriver.fill", "tray.full.fill", "doc.text.fill",
        "bookmark.fill", "flag.fill", "heart.fill", "star.fill",
        "cloud.fill", "network", "leaf.fill", "bell.fill",
        "atom", "ant.fill", "swift", "command",
    ]
}

struct ProjectIconView: View {
    let icon: String
    var size: CGFloat = 14
    var foreground: Color? = nil

    private var isSystemSymbol: Bool {
        NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil
    }

    var body: some View {
        if isSystemSymbol {
            if let foreground {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(foreground)
            } else {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .medium))
            }
        } else {
            Text(icon)
                .font(.system(size: max(10, size + 2)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct ProjectIconButton: View {
    let icon: String?
    var color: ProjectColor? = nil
    var size: CGFloat = 36
    var onSelect: (String?) -> Void

    @State private var showingPicker = false
    @State private var isHovering = false

    private var cornerRadius: CGFloat {
        size > 36 ? DesignRadius.md : DesignRadius.sm
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color?.swiftUIColor.opacity(0.12) ?? (isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
                    .frame(width: size, height: size)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(color?.swiftUIColor.opacity(0.3) ?? (isHovering ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1)), lineWidth: 1)
                    }

                if let icon, !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ProjectIconView(icon: icon, size: size * 0.5, foreground: color?.swiftUIColor ?? .primary)
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: size * 0.42, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            ProjectIconPickerPopover(
                selectedIcon: Binding(
                    get: { icon },
                    set: { onSelect($0) }
                ),
                projectColor: color,
                onChange: { newIcon in
                    onSelect(newIcon)
                },
                onDismiss: {
                    showingPicker = false
                }
            )
        }
        .help(icon == nil ? NSLocalizedString("Add project icon", comment: "") : NSLocalizedString("Change project icon", comment: ""))
    }
}

struct ProjectIconPickerPopover: View {
    @Binding var selectedIcon: String?
    var projectColor: ProjectColor? = nil
    var onChange: (String?) -> Void
    var onDismiss: (() -> Void)? = nil

    @State private var selectedTab: IconTab = .emoji
    @State private var customText: String = ""

    enum IconTab: String, CaseIterable, Identifiable {
        case emoji
        case symbols

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .emoji: "Emoji"
            case .symbols: "Symbols"
            }
        }
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(IconTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                if selectedIcon != nil {
                    Button("Remove Icon") {
                        selectedIcon = nil
                        onChange(nil)
                        onDismiss?()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    let items = selectedTab == .emoji ? ProjectIconCatalog.emojis : ProjectIconCatalog.symbols
                    ForEach(items, id: \.self) { item in
                        let isSelected = selectedIcon == item
                        Button {
                            selectedIcon = item
                            onChange(item)
                            onDismiss?()
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous)
                                    .fill(isSelected ? (projectColor?.swiftUIColor.opacity(0.2) ?? Color.accentColor.opacity(0.15)) : Color.clear)
                                    .overlay {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: DesignRadius.xs, style: .continuous)
                                                .stroke(projectColor?.swiftUIColor ?? Color.accentColor, lineWidth: 1.5)
                                        }
                                    }

                                ProjectIconView(icon: item, size: selectedTab == .emoji ? 16 : 14, foreground: projectColor?.swiftUIColor ?? .primary)
                            }
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 150)

            Divider()

            HStack(spacing: 6) {
                TextField("Custom emoji or symbol…", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        applyCustomText()
                    }

                Button("Apply") {
                    applyCustomText()
                }
                .font(.caption)
                .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help(NSLocalizedString("Open Character Viewer", comment: "Opens native macOS emoji picker"))
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func applyCustomText() {
        let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedIcon = trimmed
        onChange(trimmed)
        onDismiss?()
    }
}

struct ProjectIconPickerSheet: View {
    let project: Project
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var currentIcon: String?

    init(project: Project, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.project = project
        self.onSave = onSave
        self.onCancel = onCancel
        _currentIcon = State(initialValue: project.icon)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Project Icon")
                .font(.headline)

            ProjectIconPickerPopover(
                selectedIcon: $currentIcon,
                projectColor: project.color,
                onChange: { _ in }
            )

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Done") {
                    onSave(currentIcon)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
