import SwiftUI

/// Rider-authored planning preferences.
///
/// The loop planner already applies a bounded cost multiplier for names listed
/// here (see `RoadPreferences.multiplier`). This screen is the only way to set
/// them, and the only way to forget what the planner learned on its own from
/// rides the rider actually started.
struct RoadPreferencesView: View {
    @State private var preferred: [String] = []
    @State private var avoided: [String] = []
    @State private var learnedCount = 0
    @State private var preferredDraft = ""
    @State private var avoidedDraft = ""
    @State private var confirmingForgetLearned = false
    @State private var confirmingClearAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RevertScreenHeader(
                    eyebrow: "ROUTE TASTE",
                    title: "Roads you know",
                    subtitle: "The loop planner nudges towards roads you like and away from roads you don't. Everything stays on this iPhone.",
                    systemImage: "road.lanes"
                )

                roadList(
                    title: "Prefer",
                    icon: "hand.thumbsup.fill",
                    tint: MapUI.emerald,
                    names: preferred,
                    draft: $preferredDraft,
                    emptyHint: "Add a road you always enjoy riding. It gets a small discount when the planner scores loops.",
                    add: { name in
                        RouteTaste.shared.prefer(name)
                        refresh()
                    },
                    remove: { name in
                        RouteTaste.shared.stopPreferring(name)
                        refresh()
                    }
                )

                roadList(
                    title: "Avoid",
                    icon: "hand.thumbsdown.fill",
                    tint: MapUI.amber,
                    names: avoided,
                    draft: $avoidedDraft,
                    emptyHint: "Add a road to steer loops away from. Gravel, roadworks and the motorway all work here.",
                    add: { name in
                        RouteTaste.shared.avoid(name)
                        refresh()
                    },
                    remove: { name in
                        RouteTaste.shared.stopAvoiding(name)
                        refresh()
                    }
                )

                learnedCard

                RevertInfoNote(
                    text: "Preferences only steer loop planning. A route planned to a specific destination still follows the road network, whatever is listed here.",
                    systemImage: "info.circle"
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .pulseBackground()
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
    }

    // MARK: - Cards

    private func roadList(
        title: String,
        icon: String,
        tint: Color,
        names: [String],
        draft: Binding<String>,
        emptyHint: String,
        add: @escaping (String) -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RevertCardHeader(icon: icon, title: title, tint: tint,
                             trailingText: names.isEmpty ? nil : "\(names.count)")

            HStack(spacing: 8) {
                TextField("Road name", text: draft)
                    .font(.system(.subheadline, design: .rounded))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commit(draft) { add($0) } }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(MapUI.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MapUI.line, lineWidth: 0.8)
                    }

                Button("Add") { commit(draft) { add($0) } }
                    .font(.scaledSystem(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(tint.opacity(0.12), in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }

            if names.isEmpty {
                RevertInfoNote(text: emptyHint, systemImage: "mappin.slash")
            } else {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 10) {
                        Image(systemName: "road.lanes")
                            .font(.scaledSystem(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 26, height: 26)
                            .background(tint.opacity(0.10), in: Circle())

                        Text(name)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(MapUI.ink)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Button {
                            RevertHaptics.tap()
                            remove(name)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.scaledSystem(size: 10, weight: .bold))
                                .foregroundStyle(MapUI.textTertiary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(name)")
                    }
                }
            }
        }
        .padding(14)
        .revertCard()
    }

    private var learnedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RevertCardHeader(
                icon: "sparkles",
                title: "Learned from your rides",
                tint: MapUI.cyan,
                trailingText: learnedCount == 0 ? "Nothing yet" : "\(learnedCount) road\(learnedCount == 1 ? "" : "s")"
            )

            RevertInfoNote(
                text: "Starting a loop gives its roads a small preference next time. Forget them if a road has changed or the planner keeps choosing somewhere you no longer like.",
                systemImage: "info.circle"
            )

            HStack(spacing: 9) {
                Button {
                    RevertHaptics.tap()
                    confirmingForgetLearned = true
                } label: {
                    Label("Forget learned roads", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PulseGhostButtonStyle(compact: true))
                .disabled(learnedCount == 0)
                .opacity(learnedCount == 0 ? 0.5 : 1)

                Button {
                    RevertHaptics.tap()
                    confirmingClearAll = true
                } label: {
                    Label("Clear everything", systemImage: "trash")
                }
                .buttonStyle(PulseGhostButtonStyle(compact: true))
                .disabled(learnedCount == 0 && preferred.isEmpty && avoided.isEmpty)
                .opacity(learnedCount == 0 && preferred.isEmpty && avoided.isEmpty ? 0.5 : 1)
            }
        }
        .padding(14)
        .revertCard()
        .confirmationDialog("Forget every road the planner learned?", isPresented: $confirmingForgetLearned, titleVisibility: .visible) {
            Button("Forget learned roads", role: .destructive) {
                RouteTaste.shared.clearLearned()
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Roads you added by hand are kept.")
        }
        .confirmationDialog("Clear every road preference?", isPresented: $confirmingClearAll, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                RouteTaste.shared.clearAll()
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the roads you added and everything the planner learned.")
        }
    }

    // MARK: - State

    private func commit(_ draft: Binding<String>, apply: (String) -> Void) {
        let name = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        RevertHaptics.success()
        apply(name)
        draft.wrappedValue = ""
    }

    private func refresh() {
        let snapshot = RouteTaste.shared.snapshot()
        preferred = snapshot.preferred.sorted()
        avoided = snapshot.avoided.sorted()
        learnedCount = snapshot.learned.count
    }
}
