
import WidgetKit
import SwiftUI

@main
struct TrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainWidget()
        if #available(iOS 18.0, *) {
            TrainWidgetControl()
        }
        TrainWidgetLiveActivity()
    }
}
