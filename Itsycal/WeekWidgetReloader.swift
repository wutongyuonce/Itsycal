import Foundation
import WidgetKit

@objc public final class WeekWidgetReloader: NSObject {
    @objc public static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ItsycalWeek")
    }
}
