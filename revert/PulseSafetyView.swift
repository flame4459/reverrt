import SwiftUI
import UIKit

/// The safety centre from the Midnight Pulse concept. Every switch here writes
/// the same UserDefaults keys the map, cockpit and alert engine already read,
/// so this screen changes real riding behaviour rather than a demo state.
struct PulseSafetyView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("alert.overLimit") private var speedLimitWarnings = true
    @AppStorage("alert.curves") private var curveAlerts = true
    @AppStorage("alert.surface") private var surfaceAlerts = true
    @AppStorage("alert.haptics") private var haptics = true

    @AppStorage("alert.stop") private var stopSigns = true
    @AppStorage("alert.signal") private var trafficLights = true
    @AppStorage("alert.cameras") private var cameras = true
    @AppStorage("alert.rail") private var railCrossings = true
    @AppStorage("alert.school") private var schoolZones = true
    @AppStorage("alert.roundabout") private var roundabouts = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                hero
                preferences
                aheadOfYou
                preview
                footer
            }
            .padding(.horizontal, PulseMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .pulseBackground()
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        PulseScreenHeader(eyebrow: "RIDE AWARE", title: "Safety center") {
            PulseCircleButton(systemImage: "xmark", tint: Pulse.mutedStrong, label: "Close safety center") {
                dismiss()
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("RIDER SAFETY")
                    .font(PulseType.eyebrow)
                    .tracking(2)
                    .foregroundStyle(Pulse.accent)
                Spacer()
                PulseTag(text: "Settings ready", systemImage: "checkmark.shield.fill")
            }

            Text("Awareness,\nnot distraction.")
                .font(PulseType.display(30))
                .tracking(-0.9)
                .foregroundStyle(Pulse.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose the warnings you want while riding. Alerts only use signs on the active route and stay silent below walking speed.")
                .font(.system(size: 12))
                .foregroundStyle(Pulse.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                .fill(Pulse.heroGradient)
                .overlay {
                    RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                        .strokeBorder(Pulse.accentDeep.opacity(0.42), lineWidth: 0.8)
                }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Alert preferences")

            VStack(spacing: 0) {
                PulseToggleRow(
                    title: "Speed limit warnings",
                    subtitle: "Only after you stay over the posted limit",
                    isOn: $speedLimitWarnings
                )
                divider
                PulseToggleRow(
                    title: "Curve alerts",
                    subtitle: "Warn before tight bends, matched to your pace",
                    isOn: $curveAlerts
                )
                divider
                PulseToggleRow(
                    title: "Road surface alerts",
                    subtitle: "Unpaved and loose surfaces on the route",
                    isOn: $surfaceAlerts
                )
                divider
                PulseToggleRow(
                    title: "Haptic feedback",
                    subtitle: "Silent handlebar pulse with each alert",
                    isOn: $haptics
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Pulse.line, lineWidth: 0.8)
            }
        }
    }

    private var aheadOfYou: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Ahead of you")

            VStack(spacing: 0) {
                PulseToggleRow(title: "Stop signs", isOn: $stopSigns)
                divider
                PulseToggleRow(title: "Traffic lights", isOn: $trafficLights)
                divider
                PulseToggleRow(title: "Speed & red-light cameras", isOn: $cameras)
                divider
                PulseToggleRow(title: "Railroad crossings", isOn: $railCrossings)
                divider
                PulseToggleRow(title: "School zones", isOn: $schoolZones)
                divider
                PulseToggleRow(title: "Roundabouts", isOn: $roundabouts)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Pulse.line, lineWidth: 0.8)
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.top, 2)
                Text("Camera alerts may be restricted where you ride. Always follow road signs and conditions.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10))
            .foregroundStyle(Pulse.muted)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Alert preview")

            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                Speaker.shared.say(Narrator.exampleAlert)
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Pulse.warning)
                        .frame(width: 40, height: 40)
                        .background(Pulse.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sharp curve ahead")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Pulse.ink)
                        Text("Hear and feel a real alert from the engine")
                            .font(.system(size: 10))
                            .foregroundStyle(Pulse.muted)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Pulse.accent)
                }
                .padding(13)
                .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Pulse.line, lineWidth: 0.8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RevertCardButtonStyle())
            .accessibilityLabel("Play an alert preview")
        }
    }

    private var footer: some View {
        Text("The warning distance uses your speed, reaction time and estimated braking distance. Fine-tune thresholds, cameras and surface alerts in Settings.")
            .font(.system(size: 10))
            .foregroundStyle(Pulse.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle()
            .fill(Pulse.lineSoft)
            .frame(height: 0.8)
    }
}
