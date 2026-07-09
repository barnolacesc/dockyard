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
