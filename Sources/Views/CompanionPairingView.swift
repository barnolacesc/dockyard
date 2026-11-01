// ABOUTME: Pairing popover and QR code view for connecting the Dockyard Mobile Companion PWA.
// ABOUTME: Displays connection URLs, QR code, active client count, and security token rotation.

import CoreImage.CIFilterBuiltins
import SwiftUI

struct CompanionPairingView: View {
    @ObservedObject private var server = CompanionServer.shared
    @AppStorage("dockyard.tmuxMode") private var tmuxMode: Bool = true
    @State private var useTailscale: Bool = false
    @State private var copied: Bool = false
    @State private var copiedToken: Bool = false

    private var activeURL: URL? {
        if useTailscale, let tailscale = server.tailscaleURL {
            return tailscale
        }
        return server.localURL ?? server.tailscaleURL
    }

    private var urlString: String {
        activeURL?.absoluteString ?? ""
    }

    private var clientStatusText: String {
        if server.connectedClientsCount == 0 {
            return NSLocalizedString("Waiting for phone...", comment: "")
        } else if server.connectedClientsCount == 1 {
            return NSLocalizedString("1 device connected", comment: "")
        } else {
            return String(format: NSLocalizedString("%d devices connected", comment: ""), server.connectedClientsCount)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()

            if server.isRunning {
                runningContent
            } else {
                stoppedContent
            }
        }
        .padding(18)
        .frame(width: 320)
        .onAppear {
            if server.tailscaleIP != nil {
                useTailscale = true
            }
            if !tmuxMode {
                tmuxMode = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(server.isRunning ? DesignColor.statusSuccess.opacity(0.15) : Color.secondary.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 16))
                    .foregroundStyle(server.isRunning ? DesignColor.statusSuccess : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Mobile Companion")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(server.isRunning ? NSLocalizedString("Online • Ready to pair", comment: "") : NSLocalizedString("Offline", comment: ""))
                    .font(.caption)
                    .foregroundStyle(server.isRunning ? DesignColor.statusSuccess : .secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { server.isRunning },
                set: { enabled in
                    if enabled {
                        server.start()
                    } else {
                        server.stop()
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    // MARK: - Running Content

    private var runningContent: some View {
        VStack(spacing: 14) {
            if server.tailscaleIP != nil {
                Picker(selection: $useTailscale, label: EmptyView()) {
                    Text("Tailscale").tag(true)
                    Text("Local Wi-Fi").tag(false)
                }
                .pickerStyle(.segmented)
            }

            // QR Code Container
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 190, height: 190)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)

                if let qrImage = generateQRCode(from: urlString) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 170, height: 170)
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 4)

            Text("Scan with your phone's camera, then tap 'Add to Home Screen' in Safari.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !tmuxMode {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignColor.statusWarning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Persistent Sessions Required")
                            .font(.caption.bold())
                        Text("Enable Tmux Mode to mirror agents.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Enable") {
                        tmuxMode = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(DesignColor.statusWarning.opacity(0.1))
                .cornerRadius(8)
            } else {
                Text("Agents mirror to your phone when running in Tmux Mode. Relaunch or open a workstream to attach.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Connection Details & Actions
            VStack(spacing: 8) {
                HStack {
                    Label(
                        clientStatusText,
                        systemImage: server.connectedClientsCount > 0 ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
                    )
                    .font(.caption)
                    .foregroundStyle(server.connectedClientsCount > 0 ? DesignColor.statusSuccess : .secondary)

                    Spacer()

                    Button {
                        copyURL()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy URL")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack {
                    if let url = activeURL {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text("Open in Browser")
                            }
                            .font(.caption)
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        server.rotateToken()
                    } label: {
                        Text("Reset Token")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("Invalidates the current pairing URL and disconnects active phones.", comment: ""))
                }

                HStack(spacing: 4) {
                    Text("Token:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(server.token)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        copyToken()
                    } label: {
                        Image(systemName: copiedToken ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("Copy security token", comment: ""))
                }
            }
        }
    }

    // MARK: - Stopped Content

    private var stoppedContent: some View {
        VStack(spacing: 12) {
            Text("Control and observe coding agents on this Mac from your phone without cloud services.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)

            Button {
                server.start()
            } label: {
                Label("Start Companion Server", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(server.token, forType: .string)
        copiedToken = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToken = false
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 8.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = output.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
