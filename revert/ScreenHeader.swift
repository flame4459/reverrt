import SwiftUI

enum ScreenHeaderVariant {
    /// Dashboard-style header: eyebrow, large title, optional subtitle, no icon.
    case dashboard
    /// Detail/sheet header: leading icon, slightly smaller title.
    case detail
    /// Compact header for a future navigation-bar replacement. Not adopted yet.
    case compact
}

/// The single header layout used by every screen.
///
/// `PulseScreenHeader` and `RevertScreenHeader` remain as thin compatibility
/// wrappers so the existing call sites keep their current visual treatment.
struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = Pulse.accent
    var variant: ScreenHeaderVariant = .dashboard
    var identifier: String? = nil
    let trailing: Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        tint: Color = Pulse.accent,
        variant: ScreenHeaderVariant = .dashboard,
        identifier: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.variant = variant
        self.identifier = identifier
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: stackSpacing) {
            if variant == .detail, let systemImage {
                RevertIconBadge(systemImage: systemImage, tint: tint, size: 42)
            }

            VStack(alignment: .leading, spacing: textSpacing) {
                if showsEyebrow {
                    Text(eyebrow.uppercased())
                        .font(PulseType.eyebrow)
                        .tracking(2)
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.scaledSystem(size: titleSize, weight: .heavy))
                    .tracking(titleTracking)
                    .foregroundStyle(Pulse.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier(ifPresent: identifier)

                if let subtitle {
                    Text(subtitle)
                        .font(.scaledSystem(size: subtitleSize))
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .contain)
    }

    private var showsEyebrow: Bool { variant != .compact }

    private var titleSize: CGFloat {
        switch variant {
        case .dashboard: 27
        case .detail: 25
        case .compact: 22
        }
    }

    private var subtitleSize: CGFloat {
        switch variant {
        case .dashboard: 12
        case .detail: 12.5
        case .compact: 12
        }
    }

    private var stackSpacing: CGFloat {
        switch variant {
        case .dashboard: 12
        case .detail: 13
        case .compact: 10
        }
    }

    private var textSpacing: CGFloat {
        switch variant {
        case .dashboard: 5
        case .detail: 4
        case .compact: 3
        }
    }

    private var titleTracking: CGFloat {
        switch variant {
        case .dashboard: -0.7
        case .detail: -0.6
        case .compact: -0.4
        }
    }

    private var subtitleColor: Color {
        switch variant {
        case .dashboard, .compact: Pulse.muted
        case .detail: MapUI.textSecondary
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        tint: Color = Pulse.accent,
        variant: ScreenHeaderVariant = .dashboard,
        identifier: String? = nil
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            variant: variant,
            identifier: identifier,
            trailing: { EmptyView() }
        )
    }
}
