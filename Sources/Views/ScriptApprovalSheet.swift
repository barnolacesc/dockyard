// ABOUTME: Confirmation sheet shown before repo-provided scripts run for the first time.
// ABOUTME: Displays the exact setup/run/teardown commands so the user can review them.

import SwiftUI

struct ScriptApprovalSheet: View {
    let source: String?
    let setup: String?
    let run: String?
    let teardown: String?
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Project Scripts", systemImage: "exclamationmark.shield")
                .font(.headline)
            Text(String(
                format: NSLocalizedString(
                    "These commands come from %@ and will run in your shell. Review them before allowing Dockyard to run them.",
                    comment: "Script approval sheet explanation; %@ is the config filename"),
                source ?? ".dockyard.json"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scriptBlock(title: "Setup", script: setup)
                    scriptBlock(title: "Run", script: run)
                    scriptBlock(title: "Teardown", script: teardown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)

            HStack {
                Spacer()
                Button("Not Now", action: onDecline)
                    .keyboardShortcut(.cancelAction)
                Button("Run Scripts", action: onApprove)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func scriptBlock(title: LocalizedStringKey, script: String?) -> some View {
        if let script {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(script)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}

/// A passive heads-up shown when automatic setup is waiting for script approval.
/// Reviewing remains an explicit action; dismissing this notice never trusts or
/// executes repository-provided commands.
struct ScriptApprovalNotice: View {
    let source: String?
    let onReview: () -> Void
    let onSuppress: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Review project scripts")
                    .font(.system(size: 13, weight: .semibold))

                Text(String(
                    format: NSLocalizedString(
                        "Automatic setup is paused until you review the commands in %@.",
                        comment: "Passive script approval notice; %@ is the config filename"),
                    source ?? ".dockyard.json"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Review…", action: onReview)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Don't remind me", action: onSuppress)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}
