import SwiftUI

struct AddressSuggestionList: View {
    let suggestions: [AddressSearchService.Suggestion]
    let onSelect: (AddressSearchService.Suggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    RevertHaptics.tap()
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MapUI.cyan)
                            .frame(width: 30, height: 30)
                            .background(MapUI.cyan.opacity(0.10), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(MapUI.ink)
                                .lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(MapUI.textTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MapUI.textTertiary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RevertCardButtonStyle())
                .accessibilityLabel("\(suggestion.title), \(suggestion.subtitle)")

                if index < suggestions.count - 1 {
                    Rectangle()
                        .fill(MapUI.line)
                        .frame(height: 0.7)
                        .padding(.leading, 41)
                }
            }
        }
        .padding(.horizontal, 10)
        .background(MapUI.surfaceHigh.opacity(0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MapUI.lineStrong, lineWidth: 0.8)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
