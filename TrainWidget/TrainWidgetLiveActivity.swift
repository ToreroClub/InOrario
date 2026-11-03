import ActivityKit
import WidgetKit
import SwiftUI

struct TrainWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                // Header: Train number with Category badge and Delay status
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Text(context.attributes.category)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.18))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        
                        Text(context.attributes.trainNumber)
                            .font(.system(size: 17, weight: .black))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Delay Badge
                    Text(context.state.delay)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            context.state.delay.contains("In orario") ? Color.green.opacity(0.18) :
                            context.state.delay.contains("anticipo") ? Color.green.opacity(0.18) : Color.red.opacity(0.18)
                        )
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .red
                        )
                        .cornerRadius(8)
                }
                
                // Route Progress Visualizer
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let progressWidth = width * CGFloat(context.state.progress)
                        
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(
                                    context.state.delay.contains("In orario") ? Color.green :
                                    context.state.delay.contains("anticipo") ? Color.green : Color.orange
                                )
                                .frame(width: progressWidth, height: 4)
                            
                            Image(systemName: "tram.fill")
                                .font(.system(size: 10))
                                .foregroundColor(
                                    context.state.delay.contains("In orario") ? .green :
                                    context.state.delay.contains("anticipo") ? .green : .orange
                                )
                                .padding(3)
                                .background(Color.black)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                                .offset(x: max(0, progressWidth - 8), y: -3.5)
                        }
                    }
                    .frame(height: 12)
                    
                    HStack {
                        Text(context.attributes.origin.abbreviatedStationName())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(context.attributes.destination.abbreviatedStationName())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Footer Status Message and Last Detection Info
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .orange
                        )
                        .font(.system(size: 11))
                    Text(context.state.lastStation.isEmpty ? "--" : context.state.lastStation.abbreviatedStationName())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .orange
                        )
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(context.state.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .widgetURL(URL(string: "inorario://train/\(context.attributes.trainNumber)"))
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.category)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.18))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Text(context.attributes.trainNumber)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 6)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.delay)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            context.state.delay.contains("In orario") ? Color.green.opacity(0.18) :
                            context.state.delay.contains("anticipo") ? Color.green.opacity(0.18) : Color.red.opacity(0.18)
                        )
                        .foregroundColor(
                            context.state.delay.contains("In orario") ? .green :
                            context.state.delay.contains("anticipo") ? .green : .red
                        )
                        .cornerRadius(6)
                        .padding(.top, 6)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Small route visualizer for Dynamic Island Bottom
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                let progressWidth = geo.size.width * CGFloat(context.state.progress)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 3)
                                    
                                    Capsule()
                                        .fill(
                                            context.state.delay.contains("In orario") ? Color.green :
                                            context.state.delay.contains("anticipo") ? Color.green : Color.orange
                                        )
                                        .frame(width: progressWidth, height: 3)
                                    
                                    Image(systemName: "tram.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(
                                            context.state.delay.contains("In orario") ? .green :
                                            context.state.delay.contains("anticipo") ? .green : .orange
                                        )
                                        .padding(2)
                                        .background(Color.black)
                                        .clipShape(Circle())
                                        .offset(x: max(0, progressWidth - 6), y: -3)
                                }
                            }
                            .frame(height: 10)
                            
                            HStack {
                                Text(context.attributes.origin.abbreviatedStationName())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                Spacer()
                                Text(context.attributes.destination.abbreviatedStationName())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .foregroundColor(
                                    context.state.delay.contains("In orario") ? .green :
                                    context.state.delay.contains("anticipo") ? .green : .orange
                                )
                                .font(.system(size: 9))
                            Text(context.state.lastStation.isEmpty ? "--" : context.state.lastStation.abbreviatedStationName())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(
                                    context.state.delay.contains("In orario") ? .green :
                                    context.state.delay.contains("anticipo") ? .green : .orange
                                )
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(context.state.statusMessage)
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .foregroundColor(
                        context.state.delay.contains("In orario") ? .green :
                        context.state.delay.contains("anticipo") ? .green : .red
                    )
            } compactTrailing: {
                Text(context.state.delay)
                    .foregroundColor(
                        context.state.delay.contains("In orario") ? .green :
                        context.state.delay.contains("anticipo") ? .green : .red
                    )
                    .font(.system(size: 12, weight: .bold))
            } minimal: {
                Image(systemName: "tram.fill")
                    .foregroundColor(
                        context.state.delay.contains("In orario") ? .green :
                        context.state.delay.contains("anticipo") ? .green : .red
                    )
            }
            .widgetURL(URL(string: "inorario://train/\(context.attributes.trainNumber)"))
        }
    }
}
