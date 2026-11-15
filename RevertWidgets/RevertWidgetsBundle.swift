import WidgetKit
import SwiftUI

@main
struct RevertWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RevertQuickWidget()

        // iOS 17 gets the phone-card Live Activity. iOS 18+ also registers the
        // adaptive activity that can render the small CarPlay Dashboard / Watch
        // family. They own different activity types, so only the one the app
        // requested is ever used. WidgetBundleBuilder has no `else` branch, so
        // this is a one-sided availability check.
        NavigationLiveActivityLegacy()
        if #available(iOS 18.0, *) {
            NavigationLiveActivity()
        }
    }
}
