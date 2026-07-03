
import WidgetKit
import SwiftUI

@main
struct TrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainWidget()
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            TrainWidgetControl()
        }
        #endif
        TrainWidgetLiveActivity()
    }
}
