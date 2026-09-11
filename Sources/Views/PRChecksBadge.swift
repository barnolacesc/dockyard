// ABOUTME: Shared CI summary and check details for workstream PR surfaces.
// ABOUTME: Links preserve GitHub as the source of truth for merge eligibility.

import SwiftUI

extension GitHubCheckState {
    var color: Color {
        switch self {
        case .passed: DesignColor.statusSuccess
        case .failed: DesignColor.statusError
        case .pending, .cancelled: DesignColor.statusWarning
        case .skipped, .unknown: .secondary
        }
    }
}

struct PRChecksBadge: View {
    @EnvironmentObject private var appEnv: AppEnvironment
    let pr: GitHubPR
    let directory: String
    var compact = false
    @State private var showingDetails = false

    private var current: GitHubPR {
        guard let cached = appEnv.githubPR(for: directory, branch: pr.branch), cached.url == pr.url else { return pr }
        return cached
    }

    var body: some View {
        if current.state == "OPEN" {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                let stale = current.checksAreStale(at: context.date)
                let state = stale ? GitHubCheckState.unknown : GitHubCheck.summary(current.checks)
                let noChecks = current.checks?.isEmpty == true && !stale
                Button { showingDetails = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: noChecks ? "minus.circle" : state.symbol)
                        if !compact {
                            Text(LocalizedStringKey(current.checks?.isEmpty == true && !stale ? "No checks" : state.titleKey))
                        }
                        if let checks = current.checks, !checks.isEmpty, !stale {
                            Text(verbatim: "\(checks.filter { $0.state == .passed || $0.state == .skipped }.count)/\(checks.count)")
                                .tabularNumbers()
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(state.color.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignRadius.sm))
                    .frame(minWidth: 40, minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey(stale ? "Check status is out of date" : noChecks ? "No checks" : state.titleKey))
                .accessibilityLabel(LocalizedStringKey(current.checks?.isEmpty == true && !stale ? "No checks" : state.titleKey))
                .accessibilityHint("Show check details")
                .popover(isPresented: $showingDetails) {
                    PRChecksPopover(pr: current, directory: directory)
                        .environmentObject(appEnv)
                }
            }
        }
    }
}

private struct PRChecksPopover: View {
    @EnvironmentObject private var appEnv: AppEnvironment
    let pr: GitHubPR
    let directory: String

    private var current: GitHubPR {
        guard let cached = appEnv.githubPR(for: directory, branch: pr.branch), cached.url == pr.url else { return pr }
        return cached
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CI checks").font(.headline)
                Text(verbatim: "#\(current.number)").foregroundStyle(.secondary).tabularNumbers()
                Spacer()
                if appEnv.checksRefreshing(for: current) { ProgressView().controlSize(.small) }
                Button("Refresh") { appEnv.refreshPRChecks(current, directory: directory, force: true) }
                    .disabled(appEnv.checksRefreshing(for: current) || current.state != "OPEN")
            }
            Text(current.title).font(.subheadline).lineLimit(2)
            if current.checksAreStale(at: Date()) {
                Label("Check status is out of date", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(DesignColor.statusWarning)
            }
            if current.isDraft { prLink("Draft") }
            if current.reviewDecision == "REVIEW_REQUIRED" { prLink("Waiting for approval") }
            if current.reviewDecision == "CHANGES_REQUESTED" { prLink("Changes requested") }
            if current.reviewDecision == "APPROVED" { prLink("Review approved") }
            if current.mergeStateStatus == "DIRTY" { prLink("Merge conflicts") }
            if current.mergeStateStatus == "BLOCKED" { prLink("Merge blocked on GitHub") }

            Divider()
            if let checks = current.checks, !checks.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                            checkRow(check)
                        }
                    }
                }
                .frame(height: min(CGFloat(checks.count) * 56, 280))
                if checks.count >= 100 {
                    Text("Check details may be incomplete. Open GitHub for the full status.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(LocalizedStringKey(current.checks == nil ? "Checks unavailable" : "No checks"))
                    .foregroundStyle(.secondary)
            }
            if appEnv.requiredChecks(for: current) == nil, !appEnv.checksRefreshing(for: current) {
                Text("Required checks could not be identified.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Passing checks do not guarantee merge eligibility. GitHub may require reviews or other conditions.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                prLink("Open on GitHub")
                Spacer()
                if let url = URL(string: current.url + "/checks") {
                    Link("Open checks on GitHub", destination: url)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
        .task(id: current.checksIdentity) { appEnv.refreshPRChecks(current, directory: directory) }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            appEnv.refreshPRChecks(current, directory: directory)
        }
    }

    @ViewBuilder
    private func prLink(_ title: LocalizedStringKey) -> some View {
        if let url = URL(string: current.url) { Link(title, destination: url) }
    }

    private func checkRow(_ check: GitHubCheck) -> some View {
        HStack(spacing: 8) {
            Image(systemName: check.state.symbol).foregroundStyle(check.state.color)
            VStack(alignment: .leading, spacing: 2) {
                if let url = URL(string: check.link), ["https", "http"].contains(url.scheme ?? "") {
                    Link(destination: url) { checkName(check) }
                } else {
                    checkName(check)
                }
                Text(LocalizedStringKey(check.state.titleKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if appEnv.requiredChecks(for: current)?.contains(where: {
                $0.name == check.name && $0.link == check.link
            }) == true {
                Text("Required").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 40)
    }

    @ViewBuilder
    private func checkName(_ check: GitHubCheck) -> some View {
        if check.name.isEmpty { Text("Unnamed check") }
        else { Text(verbatim: check.workflow.isEmpty ? check.name : "\(check.workflow) / \(check.name)") }
    }
}
