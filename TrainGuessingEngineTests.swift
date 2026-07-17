import Foundation

func stationNamesMatch(_ name1: String, _ name2: String) -> Bool {
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

struct Train {
    var number: String
    var destination: String
}

struct Stop {
    var stationName: String
    var actualTime: String?
}

// MOCK DATA for tests
let originStationName = "Magenta"

func simulatePerformGuess(
    candidates: [Train],
    stopsMap: [String: [Stop]],
    lastDetectedMap: [String: String],
    currentStationName: String,
    isInMiddleOfNowhere: Bool,
    lastConsultedTrainID: String,
    currentTime: Date
) -> String {
    
    var prioritizedCandidates = candidates
    if !lastConsultedTrainID.isEmpty {
        if let consulted = candidates.first(where: { $0.number == lastConsultedTrainID }) {
            prioritizedCandidates.insert(consulted, at: 0)
        }
    }
    
    var validCandidates: [(Train, Int, Bool, Double)] = []
    
    for train in prioritizedCandidates {
        let stops = stopsMap[train.number] ?? []
        guard let originIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, originStationName) }) else { continue }
        
        let lastDetectedStation = lastDetectedMap[train.number] ?? "Magenta"
        
        if isInMiddleOfNowhere {
            let lastDetectedIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, lastDetectedStation) }) ?? originIndex
            if lastDetectedIndex >= originIndex {
                validCandidates.append((train, lastDetectedIndex - originIndex, false, Double.greatestFiniteMagnitude))
            }
        } else {
            if let currentIndex = stops.firstIndex(where: { stationNamesMatch($0.stationName, currentStationName) }) {
                if currentIndex > originIndex {
                    var isTemporalMatch = false
                    var timeDiff = Double.greatestFiniteMagnitude
                    
                    if let actualTimeStr = stops[currentIndex].actualTime {
                        let calendar = Calendar.current
                        let timeParts = actualTimeStr.split(separator: ":")
                        if timeParts.count == 2, let h = Int(timeParts[0]), let m = Int(timeParts[1]) {
                            var comps = calendar.dateComponents([.year, .month, .day], from: currentTime)
                            comps.hour = h
                            comps.minute = m
                            if let transitDate = calendar.date(from: comps) {
                                timeDiff = abs(currentTime.timeIntervalSince(transitDate))
                                if timeDiff <= 120 {
                                    isTemporalMatch = true
                                }
                            }
                        }
                    }
                    
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
        return "FAILED"
    } else {
        if let bestTemporal = validCandidates.filter({ $0.2 }).min(by: { $0.3 < $1.3 }) {
            return bestTemporal.0.number
        } else if !lastConsultedTrainID.isEmpty && validCandidates.contains(where: { $0.0.number == lastConsultedTrainID }) {
            let bestConsulted = validCandidates.first(where: { $0.0.number == lastConsultedTrainID })!
            return bestConsulted.0.number
        } else {
            let best = validCandidates.min(by: { $0.1 < $1.1 })
            return best!.0.number
        }
    }
}

func getMockTime(hours: Int, minutes: Int) -> Date {
    var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    comps.hour = hours
    comps.minute = minutes
    return Calendar.current.date(from: comps)!
}

func testDeduction_WhenLastConsultedTrainIsFalsePositive_ShouldFallbackToCorrectTrain() {
    print("Test 1: Last Consulted Train is False Positive")
    let trainA = Train(number: "S6", destination: "Treviglio")
    let trainB = Train(number: "RV", destination: "Centrale")
    let stopsA = [Stop(stationName: "Magenta"), Stop(stationName: "Corbetta", actualTime: "15:38")]
    let stopsB = [Stop(stationName: "Magenta"), Stop(stationName: "Rho Fiera", actualTime: "15:45")] // Non ferma a Corbetta
    
    let result = simulatePerformGuess(
        candidates: [trainA, trainB],
        stopsMap: ["S6": stopsA, "RV": stopsB],
        lastDetectedMap: ["S6": "Magenta", "RV": "Magenta"],
        currentStationName: "Corbetta",
        isInMiddleOfNowhere: false,
        lastConsultedTrainID: "RV", // Utente ha consultato l'RV prima di salire sull'S6
        currentTime: getMockTime(hours: 15, minutes: 38)
    )
    
    if result == "S6" {
        print("✅ PASSED: L'algoritmo ha ignorato l'RV (Falso positivo) e ha agganciato l'S6!")
    } else {
        print("❌ FAILED: Aspettavo S6, ho ottenuto \(result)")
    }
}

func testDeduction_WhenUserInMiddleOfNowhere_ShouldStillIdentifyTrainBasedOnTrajectory() {
    print("\nTest 2: Middle of Nowhere")
    let trainA = Train(number: "S6", destination: "Treviglio")
    // Simuliamo di essere "in mezzo al nulla" (nessuna stazione nel raggio di 2.5km)
    let stopsA = [Stop(stationName: "Magenta"), Stop(stationName: "Corbetta")]
    
    let result = simulatePerformGuess(
        candidates: [trainA],
        stopsMap: ["S6": stopsA],
        lastDetectedMap: ["S6": "Corbetta"], // Treno rilevato a Corbetta, l'utente e' tra Corbetta e Vittuone
        currentStationName: "CampagnaIsolata", // Questo viene ignorato dal flag
        isInMiddleOfNowhere: true,
        lastConsultedTrainID: "",
        currentTime: getMockTime(hours: 15, minutes: 40)
    )
    
    if result == "S6" {
        print("✅ PASSED: L'algoritmo ha individuato il treno sulla traiettoria anche in mezzo al nulla!")
    } else {
        print("❌ FAILED: Aspettavo S6, ho ottenuto \(result)")
    }
}

func testDeduction_TemporalCoincidence_S6_vs_RV() {
    print("\nTest 3: Temporal Coincidence (S6 transito vs RV transito in ritardo)")
    let trainA = Train(number: "S6", destination: "Treviglio")
    let trainB = Train(number: "RV", destination: "Centrale")
    
    // Entrambi transitano a Corbetta, ma in momenti diversi.
    // L'utente apre l'app alle 15:38
    let stopsA = [Stop(stationName: "Magenta"), Stop(stationName: "Corbetta", actualTime: "15:38")] // S6 coincidenza perfetta
    let stopsB = [Stop(stationName: "Magenta"), Stop(stationName: "Corbetta", actualTime: "15:34")] // RV transitato troppo tempo fa
    
    let result = simulatePerformGuess(
        candidates: [trainA, trainB],
        stopsMap: ["S6": stopsA, "RV": stopsB],
        lastDetectedMap: ["S6": "Corbetta", "RV": "Corbetta"],
        currentStationName: "Corbetta",
        isInMiddleOfNowhere: false,
        lastConsultedTrainID: "",
        currentTime: getMockTime(hours: 15, minutes: 38)
    )
    
    if result == "S6" {
        print("✅ PASSED: L'algoritmo ha usato la coincidenza temporale per scartare l'RV (transitato > 2 min fa) e scegliere l'S6!")
    } else {
        print("❌ FAILED: Aspettavo S6, ho ottenuto \(result)")
    }
}

print("=== ESECUZIONE TEST SUFFICIENTI PER LA VALIDAZIONE DEL CORE ===\n")
testDeduction_WhenLastConsultedTrainIsFalsePositive_ShouldFallbackToCorrectTrain()
testDeduction_WhenUserInMiddleOfNowhere_ShouldStillIdentifyTrainBasedOnTrajectory()
testDeduction_TemporalCoincidence_S6_vs_RV()
