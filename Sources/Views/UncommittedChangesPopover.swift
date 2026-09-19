// ABOUTME: Popover displaying uncommitted and untracked file changes with actions to inspect or discard.
// ABOUTME: Used by ProjectOverviewView and WorkstreamInfoView for transparency into git status.

import SwiftUI

struct UncommittedChangesPopover: View {
    let path: String
    let title: String
    var onDiscard: (() -> Void)? = nil
    var onCleanUntracked: (() -> Void)? = nil

    @State private var changes: [UncommittedFileChange] = []
    @State private var isLoading = true
    @State private var showingDiscardAlert = false
    @State private var showingCleanUntrackedAlert = false
    @State private var isDiscarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uncommitted Changes")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(changes.count)")
                        .font(.caption)
                        .tabularNumbers()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if changes.isEmpty {
                HStack {
                    Spacer()
                    Text("No uncommitted changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(changes) { change in
                            HStack(spacing: 8) {
                                changeBadge(change.status)
                                Text(change.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 240)
            }

            Divider()

            // Actions
            HStack(spacing: 8) {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .pressable()

                Spacer()

                if !changes.isEmpty {
                    let untrackedCount = changes.filter { $0.status == .untracked }.count
                    let modifiedCount = changes.filter { $0.status == .modified }.count

                    if untrackedCount > 0 && modifiedCount > 0 {
                        Button(action: { showingCleanUntrackedAlert = true }) {
                            Text("Clean Untracked")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .pressable()
                        .disabled(isDiscarding)
                    }

                    Button(role: .destructive, action: { showingDiscardAlert = true }) {
                        Text("Discard All")
                            .font(.caption)
                            .foregroundStyle(DesignColor.statusError)
                    }
                    .buttonStyle(.plain)
                    .pressable()
                    .disabled(isDiscarding)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear {
            loadChanges()
        }
        .alert("Discard All Changes", isPresented: $showingDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard All", role: .destructive) {
                performDiscardAll()
            }
        } message: {
            Text("Permanently discard all uncommitted changes in this worktree? This cannot be undone.")
        }
        .alert("Clean Untracked Files", isPresented: $showingCleanUntrackedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) {
                performCleanUntracked()
            }
        } message: {
            Text("Permanently delete all untracked files in this worktree?")
        }
    }

    private func changeBadge(_ status: FileGitStatus) -> some View {
        Group {
            switch status {
            case .untracked:
                Text("??")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignColor.statusSuccess)
                    .frame(width: 20)
            case .modified:
                Text("M")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignColor.statusWarning)
                    .frame(width: 20)
            case .ignored:
                Text("!!")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
    }

    private func loadChanges() {
        isLoading = true
        let targetPath = path
        Task.detached {
            let list = GitOperations.uncommittedFileChanges(at: targetPath)
            await MainActor.run {
                self.changes = list
                self.isLoading = false
            }
        }
    }

    private func performDiscardAll() {
        isDiscarding = true
        let targetPath = path
        Task.detached {
            GitOperations.discardAllChanges(at: targetPath)
            await MainActor.run {
                self.isDiscarding = false
                self.loadChanges()
                self.onDiscard?()
            }
        }
    }

    private func performCleanUntracked() {
        isDiscarding = true
        let targetPath = path
        Task.detached {
            GitOperations.cleanUntrackedFiles(at: targetPath)
            await MainActor.run {
                self.isDiscarding = false
                self.loadChanges()
                self.onCleanUntracked?()
            }
        }
    }
}
