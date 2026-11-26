import SwiftUI
import SwiftData
import UIKit

// MARK: - Route identity

/// A stable, privacy-preserving identity for a loop.
///
/// Two riders comparing times have to agree on which loop they rode, but the
/// app promises not to hand out coordinates. The key hashes the rounded start
/// cell and distance, so the shared link contains an opaque token rather than
/// a location.
nonisolated enum RouteFingerprint {
    static func key(for route: PlannedRoute) -> String {
        guard let first = route.points.first else { return "" }
        let mode = route.kind.isSprint ? "sprint" : (route.kind.isLoop ? "circuit" : "route")
        return key(length: route.length, latitude: first.lat, longitude: first.lon,
                   laps: route.kind.isLoop ? max(route.laps, 1) : 1, mode: mode)
    }

    static func key(for saved: SavedRoute) -> String {
        guard let first = saved.points.first else { return "" }
        let mode = saved.isSprint ? "sprint" : (saved.isLoop ? "circuit" : "route")
        return key(length: saved.distanceMeters, latitude: first.lat, longitude: first.lon,
                   laps: saved.isLoop ? max(saved.laps, 1) : 1, mode: mode)
    }

    static func key(length: Double, latitude: Double, longitude: Double,
                    laps: Int = 3, mode: String = "circuit") -> String {
        guard length > 0, latitude.isFinite, longitude.isFinite else { return "" }
        let miles = (length / 1_609.344 * 10).rounded() / 10
        // About a 110 m cell: close enough that the same loop start matches,
        // loose enough that GPS noise or a different parking spot still does.
        let latCell = (latitude * 1_000).rounded() / 1_000
        let lonCell = (longitude * 1_000).rounded() / 1_000
        let raw = String(format: "%@|%d|%.1f|%.3f|%.3f", mode, max(laps, 1), miles, latCell, lonCell)
        return "r" + fnv1a(raw)
    }

    private static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Result payload

/// One rider's time on a loop. This is the entire vocabulary of a shared
/// link: a name, a route label, a hashed route key and the bike numbers.
nonisolated struct RivalResult: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var rider: String
    var routeName: String
    var routeKey: String
    var durationSeconds: Double
    var distanceMeters: Double
    var maxLeanDegrees: Double
    var maxSpeedMps: Double
    var date: Date
    /// Laps covered by this result. Optional so time-only links written before
    /// laps existed still decode.
    var laps: Int? = nil
    /// Optional for the same reason. nil on links written before sprints.
    var isSprint: Bool? = nil
    /// Optional compact GPS trace, so the recipient can watch the ride replay.
    /// Time-only links leave this nil.
    var track: Data? = nil
    /// Vehicle used for the time. Optional so links written before car mode
    /// still decode; nil is treated as a motorcycle.
    var vehicleKind: String? = nil

    var vehicle: VehicleKind {
        VehicleKind(rawValue: vehicleKind ?? "") ?? .motorcycle
    }

    var hasReplay: Bool { track?.isEmpty == false }

    static func from(ride: Ride, rider: String, routeName: String?, includeTrack: Bool = true) -> RivalResult? {
        guard let key = ride.routeKey, !key.isEmpty else { return nil }
        var result = RivalResult(
            rider: rider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A rider" : rider,
            routeName: routeName ?? ride.routeName ?? "A loop",
            routeKey: key,
            durationSeconds: ride.durationSeconds,
            distanceMeters: ride.distanceMeters,
            maxLeanDegrees: ride.maxLeanAngleDegrees,
            maxSpeedMps: ride.maxSpeedMps,
            date: ride.startDate,
            laps: max(ride.laps, 1),
            isSprint: ride.isSprint,
            vehicleKind: ride.vehicleKind.rawValue
        )
        if includeTrack {
            result.track = RideTrackCodec.encode(ride.points)
        }
        return result
    }
}

/// Builds and reads `revert://rival?d=…` links.
nonisolated enum RivalLink {
    static let host = "rival"
    /// The largest link this app writes is a 200 KB trace; base64 of that plus
    /// the JSON envelope stays well under this. Reject before decoding so a
    /// hostile URL cannot force a huge allocation.
    static let maxEncodedLength = 1_000_000

    static func url(for result: RivalResult) -> URL? {
        guard let data = try? JSONEncoder().encode(result), !result.routeKey.isEmpty else { return nil }
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "revert"
        components.host = host
        components.queryItems = [URLQueryItem(name: "d", value: token)]
        return components.url
    }

    static func result(from url: URL) -> RivalResult? {
        guard url.scheme == "revert", url.host == host else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "d" })?.value,
              !token.isEmpty, token.count <= maxEncodedLength else { return nil }
        var base64 = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let decoded = try? JSONDecoder().decode(RivalResult.self, from: data) else { return nil }
        guard !decoded.routeKey.isEmpty,
              decoded.rider.count <= 60,
              decoded.routeName.count <= 120,
              decoded.durationSeconds > 0,
              decoded.durationSeconds.isFinite,
              decoded.durationSeconds <= 7 * 86_400,
              decoded.distanceMeters.isFinite,
              decoded.distanceMeters >= 0,
              decoded.distanceMeters <= 2_000_000,
              decoded.maxSpeedMps.isFinite,
              decoded.maxSpeedMps >= 0,
              decoded.maxSpeedMps <= 200,
              decoded.maxLeanDegrees.isFinite,
              decoded.maxLeanDegrees >= 0,
              decoded.maxLeanDegrees <= 90 else { return nil }
        // Do not let a malformed link allocate an unbounded replay.
        if let track = decoded.track, track.count > 200_000 { return nil }
        return decoded
    }
}

// MARK: - Store

/// Imported results live on the phone, not on a server. There is no account
/// and no leaderboard service: a leaderboard exists because two riders chose
/// to send each other a link.
@MainActor
@Observable
final class RivalBoard {
    static let shared = RivalBoard()

    private(set) var results: [RivalResult] = []
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "rivals.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func results(for routeKey: String) -> [RivalResult] {
        guard !routeKey.isEmpty else { return [] }
        return results
            .filter { $0.routeKey == routeKey }
            .sorted { $0.durationSeconds < $1.durationSeconds }
    }

    /// Returns false for a duplicate link, so re-tapping a message does not
    /// stack the same rider twice.
    @discardableResult
    func add(_ result: RivalResult) -> Bool {
        guard !result.routeKey.isEmpty else { return false }
        // Same link, or the same ride shared again with a fresh payload id.
        // Without this, re-opening a message or re-sharing a replay stacks
        // duplicate rows with identical numbers.
        let duplicate = results.contains { existing in
            existing.id == result.id
                || (existing.routeKey == result.routeKey
                    && existing.rider.caseInsensitiveCompare(result.rider) == .orderedSame
                    && abs(existing.durationSeconds - result.durationSeconds) < 1
                    && abs(existing.date.timeIntervalSince(result.date)) < 2)
        }
        guard !duplicate else { return false }
        results.append(result)
        if results.count > 500 {
            results.removeFirst(results.count - 500)
        }
        save()
        return true
    }

    @discardableResult
    func importURL(_ url: URL) -> RivalResult? {
        guard let result = RivalLink.result(from: url) else { return nil }
        return add(result) ? result : nil
    }

    func delete(_ result: RivalResult) {
        results.removeAll { $0.id == result.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RivalResult].self, from: data) else { return }
        results = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(results) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Leaderboard

/// Local-first leaderboard for one loop: your rides on this phone plus the
/// results friends sent as links. Sorted by elapsed time.
struct RouteLeaderboardView: View {
    let title: String
    let routeKey: String
    let savedRouteID: UUID?
    let routeName: String?
    var laps: Int = 1
    var isSprint = false

    private enum VehicleFilter: String, CaseIterable, Identifiable {
        case all, motorcycle, car
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .motorcycle: "Bikes"
            case .car: "Cars"
            }
        }
        func matches(_ kind: VehicleKind) -> Bool {
            switch self {
            case .all: true
            case .motorcycle: kind == .motorcycle
            case .car: kind == .car
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ride.startDate, order: .reverse) private var allRides: [Ride]
    @AppStorage("rider.name") private var riderName = ""
    @AppStorage("share.includeReplay") private var includeReplay = true
    @State private var board = RivalBoard.shared
    @State private var copied = false
    @State private var replay: ReplayTarget?
    @State private var vehicleFilter: VehicleFilter = .all

    private struct ReplayTarget: Identifiable {
        let id = UUID()
        let result: RivalResult
        let isLocal: Bool
    }

    private struct Entry: Identifiable {
        let id: String
        let rider: String
        let duration: Double
        let date: Date
        let lean: Double
        let vehicle: VehicleKind
        let isYou: Bool
        let ride: Ride?
        let rival: RivalResult?
    }

    private var myRides: [Ride] {
        allRides.filter { ride in
            if let key = ride.routeKey, !key.isEmpty, key == routeKey { return true }
            if let savedRouteID, ride.savedRouteID == savedRouteID { return true }
            if routeKey.isEmpty, let routeName, ride.routeName == routeName { return true }
            return false
        }
    }

    private var entries: [Entry] {
        let mine = myRides.map { ride in
            Entry(
                id: "you-\(String(describing: ride.persistentModelID))",
                rider: riderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : riderName,
                duration: ride.durationSeconds,
                date: ride.startDate,
                lean: ride.maxLeanAngleDegrees,
                vehicle: ride.vehicleKind,
                isYou: true,
                ride: ride,
                rival: nil
            )
        }
        let rivals = board.results(for: routeKey).map { rival in
            Entry(
                id: rival.id.uuidString,
                rider: rival.rider,
                duration: rival.durationSeconds,
                date: rival.date,
                lean: rival.maxLeanDegrees,
                vehicle: rival.vehicle,
                isYou: false,
                ride: nil,
                rival: rival
            )
        }
        return (mine + rivals).sorted { $0.duration < $1.duration }
    }

    private var visibleEntries: [Entry] {
        entries.filter { vehicleFilter.matches($0.vehicle) }
    }

    private var shareResult: RivalResult? {
        guard let best = myRides.min(by: { $0.durationSeconds < $1.durationSeconds }) else { return nil }
        return RivalResult.from(ride: best, rider: riderName, routeName: routeName ?? title,
                                includeTrack: includeReplay)
    }

    private var shareURL: URL? {
        shareResult.flatMap(RivalLink.url)
    }

    private var bestDuration: Double? {
        visibleEntries.first?.duration
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if entries.isEmpty {
                        emptyState
                    } else {
                        vehiclePicker
                        if visibleEntries.isEmpty {
                            filteredEmptyState
                        } else {
                            boardCard
                        }
                    }

                    shareCard
                    privacyNote

                    Button("Done") { dismiss() }
                        .buttonStyle(RevertSecondaryButtonStyle(minHeight: 48))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .pulseBackground()
            .navigationTitle("Rivals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        RevertHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close leaderboard")
                }
            }
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .onAppear {
            if CommandLine.arguments.contains("-debugLeaderboardCars") {
                vehicleFilter = .car
            } else if CommandLine.arguments.contains("-debugLeaderboardBikes") {
                vehicleFilter = .motorcycle
            }
        }
        #endif
        .sheet(item: $replay) { target in
            SharedRideReplayView(result: target.result, isLocal: target.isLocal)
        }
        #if DEBUG
        .onAppear {
            guard CommandLine.arguments.contains("-debugReplay") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let entry = entries.first(where: { $0.rival?.hasReplay == true })
                    ?? entries.first(where: { $0.ride != nil }) {
                    openReplay(entry)
                }
            }
        }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.scaledSystem(size: 17, weight: .bold))
                    .foregroundStyle(MapUI.amber)
                    .frame(width: 42, height: 42)
                    .background(MapUI.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOCAL LEADERBOARD")
                        .font(RevertType.eyebrow)
                        .tracking(1.8)
                        .foregroundStyle(MapUI.amber)
                    Text(title)
                        .font(RevertType.display(23, weight: .heavy))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                if isSprint {
                    Label("Sprint", systemImage: "flag.checkered")
                } else {
                    Label("\(laps) lap\(laps == 1 ? "" : "s")", systemImage: "arrow.triangle.2.circlepath")
                }
                Text("•")
                Label("\(visibleEntries.count) time\(visibleEntries.count == 1 ? "" : "s")", systemImage: "person.2.fill")
                if let best = bestDuration {
                    Text("•")
                    Text("Best \(Units.clock(best))")
                        .foregroundStyle(MapUI.emerald)
                }
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(MapUI.textSecondary)

            Text("Times live on this iPhone. Friends send theirs as a link; nothing is uploaded.")
                .font(.scaledSystem(size: 11, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MapUI.surfaceHigh.opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(MapUI.line, lineWidth: 0.8)
                }
        }
    }

    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            RevertSectionLabel(title: "Vehicle", detail: "Shared board")
            RevertOptionPicker(options: VehicleFilter.allCases,
                               selection: $vehicleFilter,
                               title: { $0.title })
            Text("Times from bikes and cars share this board. The vehicle is noted with each result.")
                .font(.scaledSystem(size: 10, design: .rounded))
                .foregroundStyle(MapUI.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .revertCard()
    }

    private var filteredEmptyState: some View {
        RevertInfoNote(
            text: vehicleFilter == .car
                ? "No car times on this board yet."
                : "No motorcycle times on this board yet.",
            systemImage: vehicleFilter == .car ? "car.fill" : "motorcycle",
            tint: MapUI.textTertiary
        )
    }

    private var boardCard: some View {
        VStack(spacing: 8) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 11) {
                    rankBadge(index + 1)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(entry.rider)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(entry.isYou ? MapUI.emerald : MapUI.ink)
                                .lineLimit(1)
                            if entry.isYou {
                                Text("YOU")
                                    .font(.scaledSystem(size: 7, weight: .heavy, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(MapUI.emerald)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(MapUI.emerald.opacity(0.12), in: Capsule())
                            }
                        }
                        HStack(spacing: 4) {
                            Image(systemName: entry.vehicle.icon)
                                .font(.scaledSystem(size: 8, weight: .bold))
                            Text(entry.vehicle.title)
                            Text("·")
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.scaledSystem(size: 9.5, design: .rounded))
                        .foregroundStyle(MapUI.textTertiary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Units.clock(entry.duration))
                            .font(RevertType.number(15))
                            .foregroundStyle(index == 0 ? MapUI.amber : MapUI.ink)
                            .monospacedDigit()
                        if entry.vehicle == .motorcycle {
                            Text("\(Int(entry.lean.rounded()))° lean")
                                .font(.scaledSystem(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(MapUI.textTertiary)
                        } else {
                            Text(entry.vehicle.title)
                                .font(.scaledSystem(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(MapUI.textTertiary)
                        }
                    }

                    if canReplay(entry) {
                        Button {
                            RevertHaptics.tap()
                            openReplay(entry)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.scaledSystem(size: 22, weight: .bold))
                                .foregroundStyle(MapUI.cyan)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Watch \(entry.rider)'s ride replay")
                    }
                }
                .padding(10)
                .background(
                    entry.isYou ? MapUI.emerald.opacity(0.07) : MapUI.surface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .contextMenu {
                    if canReplay(entry) {
                        Button {
                            openReplay(entry)
                        } label: {
                            Label("Watch replay", systemImage: "play.circle")
                        }
                    }
                    if !entry.isYou,
                       let rival = board.results.first(where: { $0.id.uuidString == entry.id }) {
                        Button("Remove \(rival.rider)'s time", role: .destructive) {
                            board.delete(rival)
                        }
                    }
                }
            }
        }
        .revertCard()
    }

    private func canReplay(_ entry: Entry) -> Bool {
        entry.ride != nil || entry.rival?.hasReplay == true
    }

    private func openReplay(_ entry: Entry) {
        if let rival = entry.rival, rival.hasReplay {
            replay = ReplayTarget(result: rival, isLocal: false)
            return
        }
        guard let ride = entry.ride else { return }
        var result = RivalResult(
            rider: entry.rider,
            routeName: routeName ?? title,
            routeKey: routeKey,
            durationSeconds: ride.durationSeconds,
            distanceMeters: ride.distanceMeters,
            maxLeanDegrees: ride.maxLeanAngleDegrees,
            maxSpeedMps: ride.maxSpeedMps,
            date: ride.startDate,
            laps: max(ride.laps, 1),
            isSprint: ride.isSprint,
            vehicleKind: ride.vehicleKind.rawValue
        )
        result.track = RideTrackCodec.encode(ride.points)
        replay = ReplayTarget(result: result, isLocal: true)
    }

    private func rankBadge(_ rank: Int) -> some View {
        Group {
            switch rank {
            case 1:
                Image(systemName: "trophy.fill").foregroundStyle(MapUI.amber)
            case 2:
                Image(systemName: "medal.fill").foregroundStyle(Color(white: 0.78))
            case 3:
                Image(systemName: "medal.fill").foregroundStyle(Color(red: 0.80, green: 0.52, blue: 0.28))
            default:
                Text("\(rank)")
                    .font(.scaledSystem(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
            }
        }
        .font(.scaledSystem(size: 15, weight: .bold))
        .frame(width: 30, height: 30)
        .background(MapUI.surfaceHigh.opacity(0.7), in: Circle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No times yet")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(MapUI.ink)
            Text("Ride this loop, then share the link below. When a friend sends their time back, it lands here and the list sorts itself.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(MapUI.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .revertCard()
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            RevertSectionLabel(title: "Share the challenge", detail: "No server")

            if let shareURL {
                Toggle("Include the ride replay", isOn: $includeReplay)
                    .tint(MapUI.cyan)
                    .font(.system(.subheadline, design: .rounded))

                Text(includeReplay
                     ? "The link carries the GPS trace, so the other rider can watch the replay."
                     : "Time only. No coordinates travel with this link.")
                    .font(.scaledSystem(size: 10, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ShareLink(
                    item: shareURL,
                    subject: Text("Revert ride on \(title)"),
                    message: Text("Beat my time on \(title): \(Units.clock(myRides.min(by: { $0.durationSeconds < $1.durationSeconds })?.durationSeconds ?? 0))")
                ) {
                    Label(shareResult?.vehicle == .car
                          ? (includeReplay ? "Share my best drive" : "Share my best drive time")
                          : (includeReplay ? "Share my best ride" : "Share my best time"),
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(RevertPrimaryButtonStyle(minHeight: 50))

                Button {
                    UIPasteboard.general.string = shareURL.absoluteString
                    copied = true
                    RevertHaptics.success()
                } label: {
                    Label(copied ? "Link copied" : "Copy link",
                          systemImage: copied ? "checkmark" : "link")
                }
                .buttonStyle(RevertSecondaryButtonStyle(minHeight: 46))
            } else {
                Text("Finish a ride on this loop to create a shareable time.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(MapUI.textTertiary)
            }
        }
        .revertCard()
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.shield")
                .font(.scaledSystem(size: 10, weight: .bold))
                .padding(.top, 2)
            Text(includeReplay
                 ? "The link carries the ride's GPS trace so your friend can watch the replay, plus your rider name, loop label, a hashed route key and the ride numbers. Nothing is uploaded."
                 : "The link carries your rider name, the loop label, a hashed route key and the ride numbers. It contains no coordinates, and no result is uploaded anywhere.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.scaledSystem(size: 10, design: .rounded))
        .foregroundStyle(MapUI.textTertiary)
        .padding(.horizontal, 2)
    }
}
