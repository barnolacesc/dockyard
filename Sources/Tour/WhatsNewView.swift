// ABOUTME: Sheet listing What's New entries grouped by release, with optional
// ABOUTME: "Show Me" buttons that launch a linked tour flow.

import SwiftUI

struct WhatsNewView: View {
    let releases: [WhatsNewRelease]
    let onShowTour: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("What's New")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(releases, id: \.version) { release in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(format: NSLocalizedString("Version %@", comment: "what's new release header"), release.version))
                                .font(.caption)
                                .tabularNumbers()
                                .foregroundStyle(.tertiary)

                            ForEach(Array(release.entries.enumerated()), id: \.offset) { _, entry in
                                entryRow(entry)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Link("Full changelog", destination: URL(string: "https://github.com/barnolacesc/dockyard/releases")!)
                    .font(.caption)
                Spacer()
                Button(action: onClose) { Text("OK") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 400)
    }

    @ViewBuilder
    private func entryRow(_ entry: WhatsNewEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString(entry.titleKey, comment: "what's new entry title"))
                    .font(.system(size: 13, weight: .semibold))
                Text(NSLocalizedString(entry.bodyKey, comment: "what's new entry body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let flowID = entry.tourFlowID {
                    Button {
                        onShowTour(flowID)
                    } label: {
                        Label("Show Me", systemImage: "play.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .padding(.top, 2)
                }
            }
        }
    }
}
