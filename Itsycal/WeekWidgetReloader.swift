import Foundation
import WidgetKit

@objc public final class WeekWidgetReloader: NSObject {
    /// Reloads both the week and month widgets; they share one snapshot.
    @objc public static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
