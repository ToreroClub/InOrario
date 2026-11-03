import Foundation
import Combine
import CoreLocation
import SwiftUI
import UserNotifications

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
    private var cancellables = Set<AnyCancellable>()
    
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
    

    
    func sendGuessNotification(for train: Train) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            let prep = self.preposizioneArticolata(per: train)
            let originName = self.guessOriginStationName.replacingOccurrences(of: "Milano ", with: "")
            
            content.title = "Sei in viaggio con In Orario?"
            content.body = "Sei \(prep)\(train.category) \(train.number) delle \(self.guessActualDepartureTime) da \(originName)?"
            content.sound = .default
            content.categoryIdentifier = "TRAIN_GUESS_CATEGORY"
            content.userInfo = [
                "train_number": train.number,
                "train_category": train.category,
                "train_destination": train.destination,
                "train_time": train.time,
                "train_delay": train.delay,
                "train_platform": train.platform
            ]
            
            let request = UNNotificationRequest(identifier: "TRAIN_GUESS_NOTIFICATION", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    private var isCurrentlyGuessing = false
    
    init() {
        // Explicitly reset the lock on a cold start of the application session
        self.activeGuessLocked = false
        
        // Listen for notification action responses
        NotificationCenter.default.publisher(for: NSNotification.Name("ConfirmTrainGuessNotification"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.confirmGuess()
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("DismissTrainGuessNotification"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.dismissGuess()
                }
            }
            .store(in: &cancellables)
    }
    
    func markStationSeen(_ stationID: String) {
        guard !stationID.isEmpty, UUID(uuidString: stationID) == nil else { return }
        print("[TrainGuessingEngine] Stazione registrata: \(stationID)")
        lastSeenStationID = stationID
        lastSeenTimestamp = Date()
    }
    
    func appEnteredActive(locationManager: LocationManager, passanteManager: PassanteManager, manager: TrainManager) {
        print("[TrainGuessingEngine] appEnteredActive chiamato. locked: \(activeGuessLocked), guess: \(String(describing: currentGuess)), lastStation: '\(lastSeenStationID)', timestamp: \(String(describing: lastSeenTimestamp))")
        guard !activeGuessLocked else { return }
        if case .found = currentGuess { return }
        
        // Don't start another guess if we are already doing one
        guard !isCurrentlyGuessing else { return }
        
        // 1. Time Decay check
        guard let lastTimestamp = lastSeenTimestamp else {
            print("[TrainGuessingEngine] Abort: nessun lastSeenTimestamp registrato.")
            return
        }
        let deltaT = Date().timeIntervalSince(lastTimestamp)
        print("[TrainGuessingEngine] deltaT da ultima stazione vista: \(Int(deltaT))s (\(Int(deltaT / 60)) min)")
        
        // 45 seconds to 75 minutes (4500s)
        if deltaT < 45 || deltaT > 4500 {
            print("[TrainGuessingEngine] Abort: deltaT (\(Int(deltaT))s) fuori dalla finestra temporale [45s, 4500s].")
            return
        }
        
        // Start guessing
        isCurrentlyGuessing = true
        currentGuess = .guessing
        
        // Ensure we have a location
        if let location = locationManager.userLocation {
            performGuess(location: location, locationManager: locationManager, passanteManager: passanteManager, trainManager: manager)
        } else {
            print("[TrainGuessingEngine] Richiedo singola posizione GPS...")
            locationManager.requestLocation()
            
            var cancellable: AnyCancellable?
            cancellable = locationManager.$userLocation
                .compactMap { $0 }
                .first()
                .setFailureType(to: Error.self)
                .timeout(.seconds(5), scheduler: RunLoop.main, customError: { URLError(.timedOut) })
                .sink(receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        print("[TrainGuessingEngine] GPS Timeout.")
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
            
            guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 150 else {
                self.currentGuess = .failed(reason: "Accuratezza GPS insufficiente")
                return
            }
            
            let allStations = LocalScrapingService.loadReferenceStations()
            guard !allStations.isEmpty else {
                print("[TrainGuessingEngine] Stazioni di riferimento non caricate.")
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
            if closest.1 > 900 {
                isInMiddleOfNowhere = true
            }
            
            let currentStation = closest.0
            print("[TrainGuessingEngine] Stazione GPS più vicina: \(currentStation.name) (\(Int(closest.1))m, inMiddle: \(isInMiddleOfNowhere))")
            
            // Find last seen station
            guard let originStation = allStations.first(where: { 
                if let vt = $0.vtID, !vt.isEmpty, vt == self.lastSeenStationID { return true }
                if $0.name.lowercased() == self.lastSeenStationID.lowercased() { return true }
                if self.stationNamesMatch($0.name, self.lastSeenStationID) { return true }
                return false
            }) else {
                print("[TrainGuessingEngine] Stazione di origine '\(self.lastSeenStationID)' non trovata.")
                self.currentGuess = .failed(reason: "Stazione di origine sconosciuta")
                return
            }
            print("[TrainGuessingEngine] Stazione di origine confermata: \(originStation.name)")
            
            // Verifica che l'utente si sia davvero allontanato dalla stazione di origine (> 800m)
            if let originCoord = originStation.coordinate {
                let originLoc = CLLocation(latitude: originCoord.latitude, longitude: originCoord.longitude)
                let dist = location.distance(from: originLoc)
                print("[TrainGuessingEngine] Distanza da origine: \(Int(dist))m, speed: \(location.speed) m/s")
                if dist < 800 {
                    print("[TrainGuessingEngine] Utente ancora vicino alla stazione di origine (<800m).")
                    self.currentGuess = .failed(reason: "Ancora vicino all'origine")
                    return
                }
            }
            
            // Se non siamo in una stazione successiva, l'utente DEVE essere in movimento a velocità da treno (>= 5.5 m/s ~ 20 km/h)
            if isInMiddleOfNowhere && location.speed < 5.5 {
                print("[TrainGuessingEngine] Utente lontano da stazioni ma fermo/lento (speed: \(location.speed) m/s). Abort.")
                self.currentGuess = .failed(reason: "Non in movimento")
                return
            }
            
            guard let lastSeenTime = self.lastSeenTimestamp else { return }
            
            let departures = await trainManager.fetchTrainsForStation(station: originStation)
            print("[TrainGuessingEngine] Recuperati \(departures.count) treni da \(originStation.name)")
            
            let calendar = Calendar.current
            let nowEpoch = Date().timeIntervalSince1970
            let hasRecentConsulted = !self.lastConsultedTrainID.isEmpty && (nowEpoch - self.lastConsultedTimestampDouble) < 2700
            let favoriteNumbers = Set(trainManager.favoriteTrains.map { $0.number })
            
            var candidates: [Train] = []
            
            for train in departures {
                let trainDateStr = train.time
                let components = trainDateStr.split(separator: ":")
                if components.count == 2,
                   let hour = Int(components[0]),
                   let minute = Int(components[1]) {
                    
                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: lastSeenTime)
                    dateComponents.hour = hour
                    dateComponents.minute = minute
                    
                    if let trainDate = calendar.date(from: dateComponents) {
                        let timeDiff = trainDate.timeIntervalSince(lastSeenTime)
                        if timeDiff >= -300 && timeDiff <= 2100 {
                            // Se siamo fuori stazione (in movimento), considera solo treni preferiti o appena consultati
                            if isInMiddleOfNowhere {
                                if favoriteNumbers.contains(train.number) || (hasRecentConsulted && train.number == self.lastConsultedTrainID) {
                                    candidates.append(train)
                                }
                            } else {
                                candidates.append(train)
                            }
                        }
                    }
                }
            }
            print("[TrainGuessingEngine] Candidati compatibili: \(candidates.map { "\($0.category) \($0.number) (\($0.time))" })")
            
            if candidates.isEmpty {
                self.currentGuess = .failed(reason: "Nessun treno candidato trovato")
                return
            }
            
            var prioritizedCandidates = candidates
            if hasRecentConsulted, let consulted = candidates.first(where: { $0.number == self.lastConsultedTrainID }) {
                prioritizedCandidates.removeAll { $0.number == consulted.number }
                prioritizedCandidates.insert(consulted, at: 0)
            }
            
            // Phase C: Apply strict transit/topological filter
            var validCandidates: [(Train, Int, Bool, Double)] = [] // Train, delta, isTemporalMatch, temporalDiff
            
            for train in prioritizedCandidates {
                let stopsResult = await trainManager.fetchLiveStops(for: train.number, destination: train.destination)
                let stops = stopsResult.stops
                
                guard let originIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, originStation.name) }) else { continue }
                
                if isInMiddleOfNowhere {
                    let lastDetectedStation = stopsResult.status.lastStation
                    if let lastDetectedIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, lastDetectedStation) }),
                       lastDetectedIndex > originIndex {
                        validCandidates.append((train, lastDetectedIndex - originIndex, false, Double.greatestFiniteMagnitude))
                    }
                } else {
                    if let currentIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, currentStation.name) }),
                       currentIndex > originIndex {
                        var isTemporalMatch = false
                        var timeDiff = Double.greatestFiniteMagnitude
                        
                        if let actualTimeStr = stops[currentIndex].actualTime {
                            let timeParts = actualTimeStr.split(separator: ":")
                            if timeParts.count == 2, let h = Int(timeParts[0]), let m = Int(timeParts[1]) {
                                var comps = calendar.dateComponents([.year, .month, .day], from: Date())
                                comps.hour = h
                                comps.minute = m
                                if let transitDate = calendar.date(from: comps) {
                                    timeDiff = abs(Date().timeIntervalSince(transitDate))
                                    if timeDiff <= 180 { // entro 3 minuti dal transito reale nella stazione corrente
                                        isTemporalMatch = true
                                    }
                                }
                            }
                        }
                        
                        let lastDetectedStation = stopsResult.status.lastStation
                        let lastDetectedIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, lastDetectedStation) }) ?? originIndex
                        let delta = currentIndex - lastDetectedIndex
                        
                        if isTemporalMatch && (delta == 0 || delta == 1) {
                            validCandidates.append((train, abs(delta), true, timeDiff))
                        }
                    }
                }
            }
            
            if validCandidates.isEmpty {
                print("[TrainGuessingEngine] Nessun candidato valido dopo l'analisi rigorosa delle fermate.")
                self.currentGuess = .failed(reason: "Nessun candidato compatibile")
            } else {
                let chosenTrain: Train
                if let bestTemporal = validCandidates.filter({ $0.2 }).min(by: { $0.3 < $1.3 }) {
                    chosenTrain = bestTemporal.0
                } else if hasRecentConsulted, let consultedMatch = validCandidates.first(where: { $0.0.number == self.lastConsultedTrainID }) {
                    chosenTrain = consultedMatch.0
                } else {
                    chosenTrain = validCandidates.min(by: { $0.1 < $1.1 })!.0
                }
                
                let stopsResult = await trainManager.fetchLiveStops(for: chosenTrain.number, destination: chosenTrain.destination)
                if let originIndex = stopsResult.stops.firstIndex(where: { stationNamesMatch($0.stationName, originStation.name) }) {
                    self.guessOriginStationName = originStation.name
                    self.guessActualDepartureTime = stopsResult.stops[originIndex].actualTime ?? chosenTrain.time
                } else {
                    self.guessOriginStationName = originStation.name
                    self.guessActualDepartureTime = chosenTrain.time
                }
                
                print("[TrainGuessingEngine] Treno indovinato con successo: \(chosenTrain.category) \(chosenTrain.number) per \(chosenTrain.destination)!")
                self.currentGuess = .found(train: chosenTrain)
            }
        }
    }
}
