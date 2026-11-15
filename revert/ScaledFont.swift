import SwiftUI
import UIKit

/// Dynamic-Type-aware system fonts that keep the design's numeric sizes at the
/// default content-size category.
///
/// SwiftUI has no `Font.system(size:relativeTo:)`, so the scaling is done with
/// `UIFontMetrics`. The text style is inferred from the base size unless a
/// caller supplies one; that keeps small labels on the caption curve and large
/// display numbers on the title curve instead of scaling everything linearly.
extension Font {
    static func scaledSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo style: Font.TextStyle? = nil
    ) -> Font {
        let textStyle = style ?? defaultTextStyle(for: size)
        let scaled = UIFontMetrics(forTextStyle: textStyle.uiKitStyle).scaledValue(for: size)
        return .system(size: scaled, weight: weight, design: design)
    }

    /// Maps a design size to the closest system text style. These thresholds
    /// follow the default point sizes of the iOS text styles.
    private static func defaultTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 34...: .largeTitle
        case 28..<34: .title
        case 22..<28: .title2
        case 20..<22: .title3
        case 17..<20: .body
        case 15..<17: .subheadline
        case 13..<15: .footnote
        case 11..<13: .caption
        default: .caption2
        }
    }
}

private extension Font.TextStyle {
    var uiKitStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
