import Foundation

struct StopsResult: Sendable {
    let stops: [Stop]
    let status: TrainStatus
    let errorMessage: String?
}

struct SmartRouteDetails: Identifiable {
    let id = UUID()
    let isDirect: Bool
    let exchangeStation: Station?
    let originStation: Station
    let destinationStation: Station
    let originTrains: [Train]
    let exchangeTrains: [Train]
}
