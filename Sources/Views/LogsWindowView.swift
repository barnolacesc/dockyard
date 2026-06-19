// ABOUTME: Displays recent and live Dockyard unified-log entries in a separate window.
// ABOUTME: Provides filtering, pause, copy, export, and diagnostic fallback actions.

import AppKit
import SwiftUI

struct LogsWindowView: View {
    @StateObject private var store = LogStore()
    @State private var search = ""
    @State private var selectedCategory: String?
    @State private var minimumLevel = LogLevel.debug
    @State private var isAtBottom = true
    @State private var exportError: String?

    private var filteredLines: [LogLine] {
        store.filtered(search: search, category: selectedCategory, minLevel: minimumLevel)
    }

    var body: some View {
        Group {
            if let errorMessage = store.errorMessage {
                errorView(errorMessage)
            } else if filteredLines.isEmpty {
                ContentUnavailableView(
                    "No Logs Yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Dockyard activity will appear here as it is recorded.")
                )
            } else {
                logList
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .toolbar { toolbarContent }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .alert(
            "Could Not Export Logs",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredLines) { line in
                        LogLineRow(line: line)
                            .id(line.id)
                        Divider()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("logs-bottom")
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: filteredLines.last?.id) { oldValue, newValue in
                guard newValue != nil, store.isFollowing, isAtBottom || oldValue == nil else { return }
                scrollToBottom(proxy)
            }
            .onChange(of: store.isFollowing) { _, isFollowing in
                guard isFollowing else { return }
                scrollToBottom(proxy)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                store.isFollowing.toggle()
            } label: {
                Label(store.isFollowing ? "Pause" : "Live", systemImage: store.isFollowing ? "pause.fill" : "play.fill")
            }

            TextField("Search logs", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Picker("Category", selection: $selectedCategory) {
                Text("All Categories").tag(nil as String?)
                ForEach(store.categories, id: \.self) { category in
                    Text(category).tag(category as String?)
                }
            }
            .frame(width: 145)

            Picker("Minimum Level", selection: $minimumLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .frame(width: 125)
        }

        ToolbarItemGroup {
            Button("Clear") { store.clear() }
                .disabled(store.lines.isEmpty)

            Button("Copy") { copyVisibleLines() }
                .disabled(filteredLines.isEmpty)

            Button("Export") {
                Task { await exportVisibleLines() }
            }
            .disabled(filteredLines.isEmpty)

            Button("Open Logs Directory") { openLogsDirectory() }
        }
    }

    private func errorView(_ errorMessage: String) -> some View {
        ContentUnavailableView {
            Label("Logs Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 6) {
                Text("Dockyard could not access the system log store.")
                Text(errorMessage)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("Open Console.app") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("logs-bottom", anchor: .bottom)
            }
        }
    }

    private func visibleText() -> String {
        filteredLines.map(\.exportText).joined(separator: "\n")
    }

    private func copyVisibleLines() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(visibleText(), forType: .string)
    }

    private func exportVisibleLines() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dockyard-logs.txt"
        panel.allowedContentTypes = [.plainText]

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return }

        do {
            try visibleText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func openLogsDirectory() {
        let url = LaunchLogger.logsDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

private struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.date.formatted(date: .omitted, time: .standard))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(line.level.label.uppercased())
                .foregroundStyle(line.level.color)
                .frame(width: 58, alignment: .leading)
            Text(line.category)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(line.message)
                .foregroundStyle(line.level.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 4)
    }
}
