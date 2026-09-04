import Foundation
import Combine
import CoreLocation
import SwiftUI

import Foundation
import Combine
import CoreLocation
import SwiftUI

enum GuessState: Equatable {
    case guessing
    case found(train: Train)
    case passante(message: String, delay: Int, westMsg: String, eastMsg: String)
    case failed(reason: String)
}

@MainActor
class TrainGuessingEngine: ObservableObject {
    @AppStorage("lastSeenStationID") var lastSeenStationID: String = ""
    @AppStorage("lastSeenTimestamp") var lastSeenTimestampDouble: Double = 0
    @AppStorage("lastConsultedTrainID") var lastConsultedTrainID: String = ""
    @AppStorage("lastConsultedTimestamp") var lastConsultedTimestampDouble: Double = 0
    
    @Published var currentGuess: GuessState? = nil
    @Published var guessOriginStationName: String = ""
    @Published var guessActualDepartureTime: String = ""
    
    // We keep this in memory, not AppStorage, so it resets each session (cold start)
    @Published var activeGuessLocked: Bool = false
    
    var lastSeenTimestamp: Date? {
        get {
            guard lastSeenTimestampDouble > 0 else { return nil }
            return Date(timeIntervalSince1970: lastSeenTimestampDouble)
        }
        set {
            lastSeenTimestampDouble = newValue?.timeIntervalSince1970 ?? 0
        }
    }
    
    var activeGuess: Train? {
        if let guess = currentGuess, case .found(let train) = guess, !activeGuessLocked {
            return train
        }
        return nil
    }
    
    var confirmedGuess: Train? {
        if let guess = currentGuess, case .found(let train) = guess, activeGuessLocked {
            return train
        }
        return nil
    }
    
    func preposizioneArticolata(per train: Train) -> String {
        let cat = train.category.uppercased()
        if cat == "S" || cat.hasPrefix("S") || cat == "RV" || cat == "RE" || cat == "IR" {
            return "sull'"
        } else {
            return "sul "
        }
    }
    
    func confirmGuess() {
        activeGuessLocked = true
    }
    
    func dismissGuess() {
        activeGuessLocked = true
        currentGuess = nil
    }
    
    private var isCurrentlyGuessing = false
    
    init() {
        // Explicitly reset the lock on a cold start of the application session
        self.activeGuessLocked = false
    }
    
    func markStationSeen(_ stationID: String) {
        lastSeenStationID = stationID
        lastSeenTimestamp = Date()
    }
    
    func appEnteredActive(locationManager: LocationManager, passanteManager: PassanteManager, manager: TrainManager) {
        guard !activeGuessLocked else { return }
        
        // Don't start another guess if we are already doing one
        guard !isCurrentlyGuessing else { return }
        
        // 1. Time Decay check
        guard let lastTimestamp = lastSeenTimestamp else { return }
        let deltaT = Date().timeIntervalSince(lastTimestamp)
        
        // 2 minutes (120s) to 50 minutes (3000s) window
        if deltaT < 120 || deltaT > 3000 {
            return
        }
        
        // Start guessing
        isCurrentlyGuessing = true
        currentGuess = .guessing
        
        // Ensure we have a location
        if let location = locationManager.userLocation {
            performGuess(location: location, locationManager: locationManager, passanteManager: passanteManager, trainManager: manager)
        } else {
            // Request location (single shot) and wait for update
            locationManager.requestLocation()
            
            // We need a mechanism to wait for the location to arrive.
            // Since locationManager publishes userLocation, we can subscribe to it once.
            var cancellable: AnyCancellable?
            cancellable = locationManager.$userLocation
                .compactMap { $0 } // Ignore nil values
                .first() // Take the first actual location
                .setFailureType(to: Error.self)
                .timeout(.seconds(5), scheduler: RunLoop.main, customError: { URLError(.timedOut) })
                .sink(receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.currentGuess = .failed(reason: "GPS Timeout")
                        self?.isCurrentlyGuessing = false
                    }
                    cancellable?.cancel()
                }, receiveValue: { [weak self] loc in
                    guard let self = self else { return }
                    self.performGuess(location: loc, locationManager: locationManager, passanteManager: passanteManager, trainManager: manager)
                    cancellable?.cancel()
                })
        }
    }
    
    private func stationNamesMatch(_ name1: String, _ name2: String) -> Bool {
        let n1 = name1.lowercased()
            .replacingOccurrences(of: "milano ", with: "")
            .replacingOccurrences(of: " passante", with: "")
            .replacingOccurrences(of: " sotterranea", with: "")
            .replacingOccurrences(of: " politecnico", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        let n2 = name2.lowercased()
            .replacingOccurrences(of: "milano ", with: "")
            .replacingOccurrences(of: " passante", with: "")
            .replacingOccurrences(of: " sotterranea", with: "")
            .replacingOccurrences(of: " politecnico", with: "")
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        return n1.contains(n2) || n2.contains(n1)
    }
    
    private func performGuess(location: CLLocation, locationManager: LocationManager, passanteManager: PassanteManager, trainManager: TrainManager) {
        Task {
            defer {
                self.isCurrentlyGuessing = false
            }
            
            let allStations = LocalScrapingService.loadReferenceStations()
            guard !allStations.isEmpty else {
                self.currentGuess = .failed(reason: "Stazioni non caricate")
                return
            }
            
            // Find current station from GPS
            let sortedCandidates = allStations.compactMap { s -> (Station, Double)? in
                guard let c = s.coordinate else { return nil }
                let dist = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                return (s, dist)
            }.sorted(by: { $0.1 < $1.1 })
            
            var isInMiddleOfNowhere = false
            guard let closest = sortedCandidates.first else {
                self.currentGuess = .failed(reason: "Nessuna stazione in memoria")
                return
            }
            if closest.1 > 2500 {
                isInMiddleOfNowhere = true
            }
            
            let currentStation = closest.0
            
            // Phase D: Passante Check
            let passanteIds = ["S01643", "S01647", "S01650", "S01648", "S01649", "S01633"] // Lancetti, Garibaldi, Dateo, Repubblica, Porta Venezia, Porta Vittoria
            if let vtID = currentStation.vtID, passanteIds.contains(vtID) {
                // Fetch the latest Passante health status dynamically
                await passanteManager.fetchTunnelHealth(manager: trainManager)
                
                self.currentGuess = .passante(
                    message: passanteManager.passanteTunnelHealthMessage,
                    delay: passanteManager.passanteTunnelAverageDelay,
                    westMsg: passanteManager.passanteTunnelWestHealthMessage,
                    eastMsg: passanteManager.passanteTunnelEastHealthMessage
                )
                return
            }
            
            // Find last seen station
            guard let originStation = allStations.first(where: { $0.id.uuidString == self.lastSeenStationID || $0.name == self.lastSeenStationID || $0.vtID == self.lastSeenStationID }) else {
                self.currentGuess = .failed(reason: "Stazione di origine sconosciuta")
                return
            }
            
            // Abort if distance from last seen is < 2km
            if let originCoord = originStation.coordinate {
                let originLoc = CLLocation(latitude: originCoord.latitude, longitude: originCoord.longitude)
                if location.distance(from: originLoc) < 2000 {
                    self.currentGuess = .failed(reason: "Ancora vicino all'origine")
                    return
                }
            }
            
            // Fetch departing trains from origin in the window [last_seen_timestamp, last_seen_timestamp + 15 min]
            guard let lastSeenTime = self.lastSeenTimestamp else { return }
            
            let departures = await trainManager.fetchTrainsForStation(station: originStation)
            
            let calendar = Calendar.current
            
            var candidates: [Train] = []
            
            for train in departures {
                // Parse train time
                let trainDateStr = train.time // e.g. "14:30"
                let components = trainDateStr.split(separator: ":")
                if components.count == 2,
                   let hour = Int(components[0]),
                   let minute = Int(components[1]) {
                    
                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: lastSeenTime)
                    dateComponents.hour = hour
                    dateComponents.minute = minute
                    
                    if let trainDate = calendar.date(from: dateComponents) {
                        let timeDiff = trainDate.timeIntervalSince(lastSeenTime)
                        // If train departs between 0 and 15 mins after we last saw the station
                        if timeDiff >= 0 && timeDiff <= 15 * 60 {
                            candidates.append(train)
                        }
                    }
                }
            }
            
            if candidates.isEmpty {
                self.currentGuess = .failed(reason: "Nessun treno candidato trovato")
                return
            }
            
            // Last Consulted logic
            var prioritizedCandidates = candidates
            let now = Date().timeIntervalSince1970
            if !self.lastConsultedTrainID.isEmpty, (now - self.lastConsultedTimestampDouble) < 3000 {
                // If the user consulted a train recently, try to evaluate it first
                if let consulted = candidates.first(where: { $0.number == self.lastConsultedTrainID }) {
                    prioritizedCandidates.insert(consulted, at: 0) // It will be evaluated first and get priority
                }
            }
            
            // Phase C: Apply transit/topological filter
            var validCandidates: [(Train, Int, Bool, Double)] = [] // Train, delta, isTemporalMatch, temporalDiff
            
            for train in prioritizedCandidates {
                let stopsResult = await trainManager.fetchLiveStops(for: train.number, destination: train.destination)
                let stops = stopsResult.stops
                
                guard let originIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, originStation.name) }) else { continue }
                
                if isInMiddleOfNowhere {
                    // Geometric progression check for Middle of Nowhere
                    // Train must have passed origin and be heading towards a destination
                    let lastDetectedStation = stopsResult.status.lastStation
                    let lastDetectedIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, lastDetectedStation) }) ?? originIndex
                    
                    if lastDetectedIndex >= originIndex {
                        // Train is moving along the path from origin. Accept it geometrically.
                        validCandidates.append((train, lastDetectedIndex - originIndex, false, Double.greatestFiniteMagnitude))
                    }
                } else {
                    // Standard transit/stop filter
                    if let currentIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, currentStation.name) }) {
                        if currentIndex > originIndex {
                            // Temporal Coincidence Check
                            var isTemporalMatch = false
                            var timeDiff = Double.greatestFiniteMagnitude
                            
                            if let actualTimeStr = stops[currentIndex].actualTime {
                                // Calculate delta T between transit and now
                                let calendar = Calendar.current
                                let timeParts = actualTimeStr.split(separator: ":")
                                if timeParts.count == 2, let h = Int(timeParts[0]), let m = Int(timeParts[1]) {
                                    var comps = calendar.dateComponents([.year, .month, .day], from: Date())
                                    comps.hour = h
                                    comps.minute = m
                                    if let transitDate = calendar.date(from: comps) {
                                        timeDiff = abs(Date().timeIntervalSince(transitDate))
                                        if timeDiff <= 120 { // 2 minutes
                                            isTemporalMatch = true
                                        }
                                    }
                                }
                            }
                            
                            let lastDetectedStation = stopsResult.status.lastStation
                            let lastDetectedIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, lastDetectedStation) }) ?? originIndex
                            let delta = currentIndex - lastDetectedIndex
                            
                            if delta >= 0 || isTemporalMatch {
                                validCandidates.append((train, delta, isTemporalMatch, timeDiff))
                            }
                        }
                    }
                }
            }
            
            if validCandidates.isEmpty {
                self.currentGuess = .failed(reason: isInMiddleOfNowhere ? "Nessun treno coerente col percorso" : "Nessun candidato ferma/transita qui")
            } else {
                let chosenTrain: Train
                if let bestTemporal = validCandidates.filter({ $0.2 }).min(by: { $0.3 < $1.3 }) {
                    chosenTrain = bestTemporal.0
                } else if !self.lastConsultedTrainID.isEmpty && validCandidates.contains(where: { $0.0.number == self.lastConsultedTrainID }) {
                    chosenTrain = validCandidates.first(where: { $0.0.number == self.lastConsultedTrainID })!.0
                } else {
                    chosenTrain = validCandidates.min(by: { $0.1 < $1.1 })!.0
                }
                
                // Resolve actual transit/departure time from the origin station
                let stopsResult = await trainManager.fetchLiveStops(for: chosenTrain.number, destination: chosenTrain.destination)
                if let originIndex = stopsResult.stops.firstIndex(where: { stationNamesMatch($0.stationName, originStation.name) }) {
                    self.guessOriginStationName = originStation.name
                    self.guessActualDepartureTime = stopsResult.stops[originIndex].actualTime ?? chosenTrain.time
                } else {
                    self.guessOriginStationName = originStation.name
                    self.guessActualDepartureTime = chosenTrain.time
                }
                
                self.currentGuess = .found(train: chosenTrain)
            }
        }
    }
}
