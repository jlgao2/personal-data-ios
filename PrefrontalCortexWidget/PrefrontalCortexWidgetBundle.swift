import WidgetKit
import SwiftUI

@main
struct PrefrontalCortexWidgetBundle: WidgetBundle {
    var body: some Widget {
        HeroWidget()
        SessionWidget()
        ReachOutWidget()
        WorkoutLockWidget()
        if #available(iOS 16.1, *) {
            WorkoutLiveActivityConfiguration()
        }
    }
}
