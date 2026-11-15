import SwiftUI
import MapKit
import SwiftData

/// The Midnight Pulse landing screen: what today's ride is, which machine is
/// active, the next route at a glance, and one-tap access to every other part
/// of the app. All numbers come from the same SwiftData store and navigation
/// session the rest of the app uses.
struct PulseHomeView: View {
    @Environment(NavigationManager.self) private var nav
    @Query(sort: \Ride.startDate, order: .reverse) private var rides: [Ride]
    @Query(sort: \Bike.createdAt, order: .reverse) private var bikes: [Bike]
    @State private var showingFeatureLab = false
    @SceneStorage("routes.destination") private var destinationDraft = ""
    @SceneStorage("routes.focusOnAppear") private var focusRoutesOnAppear = false
    @FocusState private var destinationFocused: Bool

    var onOpenRoutes: () -> Void
    var onOpenCockpit: () -> Void
    var onOpenGarage: () -> Void
    var onOpenHistory: () -> Void
    var onOpen: (PulseSheet) -> Void

    private var primaryBike: Bike? {
        bikes.first(where: \.isPrimary) ?? bikes.first
    }

    private var totalDistance: Double {
        rides.reduce(0) { $0 + $1.distanceMeters }
    }

    private var latestRide: Ride? { rides.first }

    private var nextRouteCoordinates: [CLLocationCoordinate2D] {
        if let route = nav.route { return route.coordinates }
        return latestRide?.points.map(\.coordinate) ?? []
    }

    private var nextRouteDestination: CLLocationCoordinate2D? {
        if let route = nav.route { return route.destination }
        return latestRide?.points.last?.coordinate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                hero
                quickActions
                summaryLine
                activeMachine
                nextRoute
                recentRides
                footerNote
            }
            .padding(.horizontal, PulseMetrics.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .pulseBackground()
        .sheet(isPresented: $showingFeatureLab) {
            FeatureHubView()
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(eyebrow: "WELCOME BACK",
                     title: "Your next ride",
                     variant: .compact,
                     identifier: AccessibilityID.Home.title) {
            HStack(spacing: 8) {
                PulseCircleButton(systemImage: "paintpalette.fill",
                                  label: "Color scheme",
                                  identifier: AccessibilityID.Home.colorScheme) {
                    onOpen(.settings)
                }

                Menu {
                    Button {
                        onOpen(.offline)
                    } label: {
                        Label("Offline maps", systemImage: "arrow.down.circle.fill")
                    }
                    Button {
                        RevertHaptics.tap()
                        showingFeatureLab = true
                    } label: {
                        Label("Ride Lab", systemImage: "flask.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.scaledSystem(size: 15, weight: .semibold))
                        .foregroundStyle(Pulse.accent)
                        .frame(width: 37, height: 37)
                        .background(Pulse.iconWell, in: Circle())
                        .overlay(Circle().stroke(Pulse.accentLine.opacity(0.7), lineWidth: 0.8))
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .accessibilityLabel("More")
                .accessibilityIdentifier(AccessibilityID.Home.menu)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        Group {
            if nav.route != nil {
                activeRideHero
            } else {
                planHero
            }
        }
        .padding(16)
        .background { heroBackground }
    }

    private var planHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE ROAD IS CALLING")
                .font(PulseType.eyebrow)
                .tracking(2)
                .foregroundStyle(Pulse.accent)

            Text("Where to today?")
                .font(PulseType.display(29))
                .tracking(-0.9)
                .foregroundStyle(Pulse.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.scaledSystem(size: 14, weight: .bold))
                    .foregroundStyle(Pulse.accent)

                TextField("Search a destination", text: $destinationDraft)
                    .font(.scaledSystem(size: 15, weight: .semibold))
                    .foregroundStyle(Pulse.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .submitLabel(.go)
                    .focused($destinationFocused)
                    .onSubmit(planRoute)
                    .accessibilityIdentifier(AccessibilityID.Home.destination)

                if !destinationDraft.isEmpty {
                    Button {
                        destinationDraft = ""
                        destinationFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.scaledSystem(size: 16))
                            .foregroundStyle(Pulse.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear destination")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Pulse.canvas.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(destinationFocused ? Pulse.accent.opacity(0.7) : Pulse.lineBright, lineWidth: 0.8)
            }

            Button(action: planRoute) {
                Label("Plan route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(PulsePrimaryButtonStyle())
            .accessibilityIdentifier(AccessibilityID.Home.planRoute)
        }
    }

    private var activeRideHero: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("RIDE IN PROGRESS")
                .font(PulseType.eyebrow)
                .tracking(2)
                .foregroundStyle(Pulse.accent)

            Text("Back on the road.")
                .font(PulseType.display(29))
                .tracking(-0.9)
                .foregroundStyle(Pulse.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let route = nav.route {
                HStack(spacing: 6) {
                    Image(systemName: nav.arrived ? "flag.checkered" : "location.north.fill")
                        .font(.scaledSystem(size: 10, weight: .bold))
                    Text(nav.arrived
                         ? "Arrived at \(route.displayName ?? "your destination")"
                         : (nav.step?.instruction ?? "Following the active route"))
                        .font(.scaledSystem(size: 12))
                        .lineLimit(2)
                }
                .foregroundStyle(Pulse.mutedStrong)
            }

            Button {
                RevertHaptics.tap()
                onOpenRoutes()
            } label: {
                Label("Open map", systemImage: "map.fill")
            }
            .buttonStyle(PulsePrimaryButtonStyle())
            .accessibilityIdentifier(AccessibilityID.Home.planRoute)
        }
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
            .fill(Pulse.heroGradient)
            .overlay(alignment: .topTrailing) {
                RadialGradient(
                    colors: [Pulse.accent.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 210
                )
                .clipShape(RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: PulseMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Pulse.accentDeep.opacity(0.42), lineWidth: 0.8)
            }
    }

    private func planRoute() {
        RevertHaptics.tap()
        destinationFocused = false
        focusRoutesOnAppear = true
        onOpenRoutes()
    }

    // MARK: Summary

    private var summaryLine: some View {
        HStack(spacing: 6) {
            Text("\(rides.count) \(rides.count == 1 ? "ride" : "rides")")
            Text("·")
            Text(Units.distanceText(totalDistance, decimals: 0))
            Text("·")
            Text("\(bikes.count) \(bikes.count == 1 ? "vehicle" : "vehicles")")
        }
        .font(.scaledSystem(size: 11, weight: .semibold))
        .foregroundStyle(Pulse.muted)
        .accessibilityElement(children: .combine)
    }

    // MARK: Active machine

    private var activeMachine: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Active vehicle",
                               actionTitle: "View garage",
                               action: onOpenGarage,
                               actionIdentifier: AccessibilityID.Home.viewGarage)

            Button {
                RevertHaptics.tap()
                onOpenGarage()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: primaryBike?.isCar == true ? "car.fill" : "motorcycle")
                        .font(.scaledSystem(size: 18, weight: .semibold))
                        .foregroundStyle(Pulse.accent)
                        .frame(width: 42, height: 42)
                        .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(primaryBike?.displayName ?? "Add a vehicle")
                            .font(.scaledSystem(size: 14, weight: .semibold))
                            .foregroundStyle(Pulse.ink)
                            .lineLimit(1)
                        Text(machineSubtitle)
                            .font(.scaledSystem(size: 10.5))
                            .foregroundStyle(Pulse.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.scaledSystem(size: 11, weight: .bold))
                        .foregroundStyle(Pulse.muted)
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
            .accessibilityLabel("Active vehicle, \(primaryBike?.displayName ?? "none")")
        }
    }

    private var machineSubtitle: String {
        guard let bike = primaryBike else {
            return "Track service, fuel range and maintenance"
        }
        var parts: [String] = []
        if bike.year > 0 { parts.append(String(bike.year)) }
        parts.append(Units.distanceText(bike.odometerKm * 1_000, decimals: 0))
        if bike.isServiceDue {
            parts.append("service due")
        } else {
            parts.append("\(Units.distanceText(bike.distanceToServiceKm * 1_000, decimals: 0)) to service")
        }
        return parts.joined(separator: "  •  ")
    }

    // MARK: Next route

    private var nextRoute: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(
                title: nav.route == nil
                    ? (latestRide != nil ? "Last ride" : "Your next route")
                    : "Live route",
                actionTitle: "Saved places",
                action: { onOpen(.savedPlaces) },
                actionIdentifier: AccessibilityID.Home.savedPlaces
            )

            Button {
                RevertHaptics.tap()
                onOpenRoutes()
            } label: {
                PulseRoutePreview(
                    coordinates: nextRouteCoordinates,
                    destination: nextRouteDestination,
                    tag: nav.route != nil ? "LIVE ROUTE" : (latestRide != nil ? "LAST RIDE" : "NO ROUTE YET"),
                    caption: nextRouteCaption
                )
            }
            .buttonStyle(RevertCardButtonStyle())
            .accessibilityLabel("Route preview. \(nextRouteCaption)")
        }
    }

    private var nextRouteCaption: String {
        if let route = nav.route {
            return route.displayName ?? "Active route"
        }
        if let ride = latestRide {
            return "\(RevertFormat.shortDate(ride.startDate))  •  \(Units.distanceText(ride.distanceMeters, decimals: 1))"
        }
        return "Plan a route to see it here"
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Quick access")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                quickAction("Open cockpit",
                            systemImage: "speedometer",
                            tint: Pulse.accent,
                            identifier: AccessibilityID.Home.openCockpit,
                            action: onOpenCockpit)
                quickAction("Ride insights", systemImage: "chart.bar.fill", tint: Pulse.accent) {
                    onOpen(.insights)
                }
                quickAction("Safety alerts", systemImage: "exclamationmark.triangle.fill", tint: Pulse.warning) {
                    onOpen(.safety)
                }
                quickAction("Story posters", systemImage: "photo.artframe", tint: Pulse.accent) {
                    onOpen(.posters)
                }
            }
        }
    }

    private func quickAction(_ title: String, systemImage: String, tint: Color,
                             identifier: String? = nil,
                             action: @escaping () -> Void) -> some View {
        Button {
            RevertHaptics.tap()
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.scaledSystem(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.scaledSystem(size: 11.5, weight: .semibold))
                    .foregroundStyle(Pulse.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Pulse.line, lineWidth: 0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RevertCardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(ifPresent: identifier)
    }

    // MARK: Recent rides

    private var recentRides: some View {
        VStack(alignment: .leading, spacing: 9) {
            PulseSectionHeader(title: "Recent rides",
                               actionTitle: "View history",
                               action: onOpenHistory,
                               actionIdentifier: AccessibilityID.Home.viewHistory)

            if rides.isEmpty {
                PulseEmptyState(
                    systemImage: "road.lanes",
                    title: "No rides yet",
                    message: "Open the cockpit to record your first ride, or import a GPX track from History.",
                    actionTitle: "Open cockpit",
                    action: onOpenCockpit
                )
                .pulseCard(padding: 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(rides.prefix(3)) { ride in
                        Button {
                            RevertHaptics.tap()
                            onOpenHistory()
                        } label: {
                            HStack(spacing: 11) {
                                VStack(spacing: 2) {
                                    Text(RevertFormat.dayNumber(ride.startDate))
                                        .font(PulseType.number(17))
                                        .foregroundStyle(Pulse.accent)
                                    Text(RevertFormat.monthAbbreviation(ride.startDate).uppercased())
                                        .font(.scaledSystem(size: 8, weight: .heavy))
                                        .tracking(0.8)
                                        .foregroundStyle(Pulse.muted)
                                }
                                .frame(width: 40, height: 40)
                                .background(Pulse.iconWell, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ride.routeName ?? "Recorded ride")
                                        .font(.scaledSystem(size: 12.5, weight: .semibold))
                                        .foregroundStyle(Pulse.ink)
                                        .lineLimit(1)
                                    Text("\(Units.distanceText(ride.distanceMeters, decimals: 1))  •  \(Units.clock(ride.durationSeconds))  •  \(ride.bikeDisplayName)")
                                        .font(.scaledSystem(size: 10))
                                        .foregroundStyle(Pulse.muted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Image(systemName: "chevron.right")
                                    .font(.scaledSystem(size: 10, weight: .bold))
                                    .foregroundStyle(Pulse.muted)
                            }
                            .padding(12)
                            .background(Pulse.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Pulse.line, lineWidth: 0.8)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RevertCardButtonStyle())
                    }
                }
            }
        }
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "iphone")
                .font(.scaledSystem(size: 9, weight: .bold))
                .padding(.top, 2)
            Text("Rides, bikes and routes stay on this iPhone. Ride data is only shared when you export it.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaledSystem(size: 10))
        .foregroundStyle(Pulse.muted)
        .padding(.top, 4)
    }
}

// MARK: - Route preview

struct PulseRoutePreview: View {
    let coordinates: [CLLocationCoordinate2D]
    let destination: CLLocationCoordinate2D?
    let tag: String
    let caption: String

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if coordinates.count > 1 {
                    Map(position: $camera, interactionModes: []) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(Pulse.accentDeep.opacity(0.35), lineWidth: 9)
                        MapPolyline(coordinates: coordinates)
                            .stroke(
                                LinearGradient(
                                    colors: [Pulse.accent, Pulse.accentBright],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )
                        if let destination {
                            Annotation("Destination", coordinate: destination, anchor: .center) {
                                Circle()
                                    .fill(Pulse.accentBright)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Pulse.canvas, lineWidth: 2.5))
                                    .shadow(color: Pulse.accent.opacity(0.7), radius: 6)
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .onAppear(perform: updateCamera)
                    .onChange(of: coordinates.count) { _, _ in updateCamera() }
                } else {
                    PulseRoutePreviewPlaceholder()
                }
            }
            .frame(height: 177)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                LinearGradient(
                    colors: [Pulse.canvas.opacity(0.08), Pulse.canvas.opacity(0.46)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tag)
                    .font(.scaledSystem(size: 8.5, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Pulse.accent)
                Text(caption)
                    .font(.scaledSystem(size: 12, weight: .semibold))
                    .foregroundStyle(Pulse.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Pulse.canvas.opacity(0.82), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Pulse.lineBright, lineWidth: 0.8)
            }
            .padding(10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Pulse.line, lineWidth: 0.8)
        }
    }

    private func updateCamera() {
        guard coordinates.count > 1 else { return }
        var minLat = coordinates[0].latitude
        var maxLat = minLat
        var minLon = coordinates[0].longitude
        var maxLon = minLon
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.006),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.006)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// The concept's illustrative route line, used until there is a real track to
/// frame. Kept as a vector so it stays crisp at any size and costs no assets.
struct PulseRoutePreviewPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Pulse.panelLift, Pulse.panelDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let grid = Color.white.opacity(0.05)
                var gridPath = Path()
                stride(from: 0.0, through: size.width, by: 34).forEach { x in
                    gridPath.move(to: CGPoint(x: x, y: 0))
                    gridPath.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: 0.0, through: size.height, by: 34).forEach { y in
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(gridPath, with: .color(grid), lineWidth: 0.6)

                let points = [
                    CGPoint(x: size.width * 0.06, y: size.height * 0.84),
                    CGPoint(x: size.width * 0.22, y: size.height * 0.62),
                    CGPoint(x: size.width * 0.38, y: size.height * 0.70),
                    CGPoint(x: size.width * 0.52, y: size.height * 0.34),
                    CGPoint(x: size.width * 0.68, y: size.height * 0.48),
                    CGPoint(x: size.width * 0.80, y: size.height * 0.18),
                    CGPoint(x: size.width * 0.94, y: size.height * 0.30)
                ]
                var road = Path()
                road.move(to: points[0])
                for point in points.dropFirst() { road.addLine(to: point) }
                context.stroke(road, with: .color(Pulse.accentDeep.opacity(0.35)), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                context.stroke(road, with: .color(Pulse.accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

                context.fill(Path(ellipseIn: CGRect(x: points[0].x - 5, y: points[0].y - 5, width: 10, height: 10)), with: .color(Pulse.accentBright))
                context.fill(Path(ellipseIn: CGRect(x: points[6].x - 6, y: points[6].y - 6, width: 12, height: 12)), with: .color(Pulse.accentBright))
            }
        }
    }
}
