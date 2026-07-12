// ABOUTME: Root overlay for guided tours: dims the window, spotlights the active
// ABOUTME: anchor, and shows the step card. Purely visual except the card itself.

import SwiftUI

private enum TourOverlayMetrics {
    static let spotlightPadding: CGFloat = 6
    static let cardWidth: CGFloat = 320
    static let cardMargin: CGFloat = 12
}

private struct SpotlightShape: Shape {
    let cutout: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let cutout {
            path.addRoundedRect(
                in: cutout,
                cornerSize: CGSize(width: DesignRadius.md, height: DesignRadius.md),
                style: .continuous
            )
        }
        return path
    }
}

private struct TourOverlayModifier: ViewModifier {
    @EnvironmentObject private var controller: TourController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let step = controller.currentStep {
                    let spotlight: CGRect? = step.anchor
                        .flatMap { anchors[$0] }
                        .map { proxy[$0].insetBy(dx: -TourOverlayMetrics.spotlightPadding, dy: -TourOverlayMetrics.spotlightPadding) }

                    ZStack(alignment: .topLeading) {
                        SpotlightShape(cutout: spotlight)
                            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)

                        TourStepCard(
                            step: step,
                            stepNumber: controller.stepIndex + 1,
                            stepCount: controller.activeFlow?.steps.count ?? 0,
                            isLastStep: controller.isLastStep,
                            reduceMotion: reduceMotion,
                            onNext: { controller.next() },
                            onSkip: { controller.skipStep() },
                            onQuit: { controller.quit() }
                        )
                        .frame(width: TourOverlayMetrics.cardWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(cardOffset(spotlight: spotlight, container: proxy.size))
                    }
                    .animation(reduceMotion ? nil : DesignMotion.interaction, value: step.id)
                    .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
    }

    /// Place the card below the spotlight when it fits, otherwise above;
    /// centered when there is no spotlight. Clamped to the container.
    private func cardOffset(spotlight: CGRect?, container: CGSize) -> CGSize {
        let cardWidth = TourOverlayMetrics.cardWidth
        let estimatedCardHeight: CGFloat = 180
        let margin = TourOverlayMetrics.cardMargin

        guard let spotlight else {
            return CGSize(
                width: (container.width - cardWidth) / 2,
                height: (container.height - estimatedCardHeight) / 2
            )
        }

        var x = spotlight.midX - cardWidth / 2
        x = min(max(margin, x), container.width - cardWidth - margin)

        let below = spotlight.maxY + margin
        let y: CGFloat
        if below + estimatedCardHeight + margin <= container.height {
            y = below
        } else {
            y = max(margin, spotlight.minY - margin - estimatedCardHeight)
        }
        return CGSize(width: x, height: y)
    }
}

private struct TourStepCard: View {
    let step: TourStep
    let stepNumber: Int
    let stepCount: Int
    let isLastStep: Bool
    let reduceMotion: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    let onQuit: () -> Void

    @State private var pulsing = false

    private var isActionStep: Bool {
        if case .notification = step.advance { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: NSLocalizedString("Step %d of %d", comment: "tour progress"), stepNumber, stepCount))
                .font(.caption2)
                .tabularNumbers()
                .foregroundStyle(.tertiary)

            Text(NSLocalizedString(step.titleKey, comment: "tour step title"))
                .font(.system(size: 14, weight: .semibold))

            Text(NSLocalizedString(step.bodyKey, comment: "tour step body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if isActionStep {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .opacity(pulsing ? 0.25 : 1)
                            .onAppear {
                                guard !reduceMotion else { return }
                                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                    pulsing = true
                                }
                            }
                        Text("Complete the highlighted action to continue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onSkip) { Text("Skip") }
                        .buttonStyle(.borderless)
                } else {
                    Spacer()
                    Button(action: onNext) {
                        Text(isLastStep ? "Done" : "Next")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                if !isLastStep {
                    Button(action: onQuit) { Text("Quit Tour") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignRadius.lg, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

extension View {
    func tourOverlay() -> some View {
        modifier(TourOverlayModifier())
    }
}
