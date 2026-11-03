import XCTest
@testable import In_Orario_

final class InOrarioTests: XCTestCase {

    // MARK: - 1. ViaggiaTreno Autocomplete Parsing Test
    
    func testViaggiaTrenoAutocompleteParsing() {
        let rawResponse = """
        2461 - MILANO PORTA GARIBALDI|2461-S01649-1700000000
        2463 - PIOLTELLO LIMITO|2463-S01649-1700000000
        S6 2465 - NOVARA|2465-S01649-1700000000
        """
        
        let lines = rawResponse.components(separatedBy: .newlines).filter { !$0.isEmpty }
        struct ParsedTrain {
            let number: String
            let description: String
        }
        
        let parsed: [ParsedTrain] = lines.compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard !parts.isEmpty else { return nil }
            let desc = parts[0].components(separatedBy: " - ")
            return ParsedTrain(
                number: desc[0].trimmingCharacters(in: .whitespaces),
                description: desc.count > 1 ? desc[1].trimmingCharacters(in: .whitespaces) : desc[0]
            )
        }
        
        XCTAssertEqual(parsed.count, 3, "Should parse 3 trains from autocomplete response")
        XCTAssertEqual(parsed[0].number, "2461", "Train number should be 2461")
        XCTAssertEqual(parsed[0].description, "MILANO PORTA GARIBALDI", "Destination should be MILANO PORTA GARIBALDI")
        XCTAssertEqual(parsed[2].number, "S6 2465", "Prefixed train number should be S6 2465")
    }

    // MARK: - 2. Andamento Treno Parsing Test
    
    func testAndamentoTrenoParsing() throws {
        let jsonString = """
        {
            "numeroTreno": 2461,
            "categoria": "REG",
            "origine": "NOVARA",
            "destinazione": "PIOLTELLO LIMITO",
            "ritardo": 7,
            "stazioneUltimoRilevamento": "Rho Fiera",
            "oraUltimoRilevamento": 1700000000000,
            "fermate": [
                {
                    "stazione": "Novara",
                    "ritardo": 0,
                    "programmata": 1700000000000,
                    "effettiva": 1700000000000
                },
                {
                    "stazione": "Rho Fiera",
                    "ritardo": 7,
                    "programmata": 1700002000000,
                    "effettiva": 1700002420000
                }
            ]
        }
        """
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to serialize jsonString")
            return
        }
        
        let trainNumber = String(json["numeroTreno"] as? Int ?? 0)
        let delay = json["ritardo"] as? Int ?? 0
        let lastStation = json["stazioneUltimoRilevamento"] as? String ?? ""
        let stops = json["fermate"] as? [[String: Any]] ?? []
        
        XCTAssertEqual(trainNumber, "2461")
        XCTAssertEqual(delay, 7)
        XCTAssertEqual(lastStation, "Rho Fiera")
        XCTAssertEqual(stops.count, 2)
    }

    // MARK: - 3. Trenitalia Location Filtering Test
    
    func testTrenitaliaLocationFiltering() throws {
        let jsonString = """
        [
            {"name": "MILANO CENTRALE", "id": 830001700},
            {"name": "MILANO PORTA GARIBALDI", "id": 830001645},
            {"name": "BIVIO LAMBRATE", "id": 830009999}
        ]
        """
        struct Location: Codable {
            let name: String
            let id: Int
        }
        
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let locations = try JSONDecoder().decode([Location].self, from: data)
        let validLocations = locations.filter { TrainManager.isValidStationName($0.name) }
        
        XCTAssertEqual(locations.count, 3)
        XCTAssertEqual(validLocations.count, 2, "Should filter out 'Bivio' stations")
        XCTAssertEqual(validLocations[0].name, "MILANO CENTRALE")
    }

    // MARK: - 4. Real RequestDeduplicator Test (Zero Flakiness Controller)
    
    private actor DeduplicationTestController {
        private var startedContinuation: CheckedContinuation<Void, Never>?
        private var releaseContinuation: CheckedContinuation<String, Never>?
        var executionCount = 0
        
        func executeWork() async -> String {
            executionCount += 1
            startedContinuation?.resume()
            startedContinuation = nil
            return await withCheckedContinuation { cont in
                self.releaseContinuation = cont
            }
        }
        
        func waitForOperationStart() async {
            if executionCount > 0 { return }
            await withCheckedContinuation { cont in
                self.startedContinuation = cont
            }
        }
        
        func completeOperation(with result: String) {
            releaseContinuation?.resume(returning: result)
            releaseContinuation = nil
        }
    }

    func testRealRequestDeduplicator() async {
        let deduplicator = RequestDeduplicator<String>()
        let controller = DeduplicationTestController()
        
        let results = await withTaskGroup(of: String?.self) { group -> [String] in
            // Task 1 enters first and starts the execution
            group.addTask {
                try? await deduplicator.execute(key: "GET:https://api.test/trains|X-Key=1") {
                    await controller.executeWork()
                }
            }
            
            // Wait deterministically for task 1 to start executing inside the deduplicator
            await controller.waitForOperationStart()
            
            // Launch 4 concurrent requests that attach to the in-flight task
            for _ in 1..<5 {
                group.addTask {
                    try? await deduplicator.execute(key: "GET:https://api.test/trains|X-Key=1") {
                        await controller.executeWork()
                    }
                }
            }
            
            await Task.yield()
            
            // Release the operation for all awaiting callers
            await controller.completeOperation(with: "DeduplicatedResult_S01649")
            
            var collected = [String]()
            for await r in group {
                if let val = r { collected.append(val) }
            }
            return collected
        }
        
        let execCount = await controller.executionCount
        XCTAssertEqual(results.count, 5, "All 5 concurrent requests should finish")
        XCTAssertTrue(results.allSatisfy { $0 == "DeduplicatedResult_S01649" }, "All requests should receive identical result")
        XCTAssertEqual(execCount, 1, "Only 1 physical execution should occur (the other 4 were deduplicated)")
    }

    // MARK: - 5. Real NetworkService Deduplication Key Test
    
    func testNetworkServiceDeduplicationKey() {
        func makeRequest(url: String, method: String = "GET", headers: [String: String] = [:]) -> URLRequest {
            var req = URLRequest(url: URL(string: url)!)
            req.httpMethod = method
            for (k, v) in headers {
                req.setValue(v, forHTTPHeaderField: k)
            }
            return req
        }
        
        let req1 = makeRequest(url: "https://api.example.com/data", headers: ["Accept": "application/json"])
        let req2 = makeRequest(url: "https://api.example.com/data", headers: ["Accept": "application/json"])
        let req3 = makeRequest(url: "https://api.example.com/data", headers: ["Accept": "text/html"])
        let req4 = makeRequest(url: "https://api.example.com/data", method: "POST", headers: ["Accept": "application/json"])
        let req5 = makeRequest(url: "https://api.example.com/other", headers: ["Accept": "application/json"])
        
        let key1 = NetworkService.deduplicationKey(for: req1)
        let key2 = NetworkService.deduplicationKey(for: req2)
        let key3 = NetworkService.deduplicationKey(for: req3)
        let key4 = NetworkService.deduplicationKey(for: req4)
        let key5 = NetworkService.deduplicationKey(for: req5)
        
        XCTAssertEqual(key1, key2, "Identical requests must produce identical keys")
        XCTAssertNotEqual(key1, key3, "Requests with different headers must produce different keys")
        XCTAssertNotEqual(key1, key4, "Requests with different HTTP methods must produce different keys")
        XCTAssertNotEqual(key1, key5, "Requests with different URLs must produce different keys")
    }

    // MARK: - 6. AppNetworkError Mapping & Equality Test
    
    func testAppNetworkErrors() {
        let timeout = AppNetworkError.timeout
        let timeout2 = AppNetworkError.timeout
        let cancelled = AppNetworkError.cancelled
        let http500 = AppNetworkError.httpError(statusCode: 500)
        let http500b = AppNetworkError.httpError(statusCode: 500)
        let http404 = AppNetworkError.httpError(statusCode: 404)
        
        XCTAssertEqual(timeout, timeout2)
        XCTAssertNotEqual(timeout, cancelled)
        XCTAssertEqual(http500, http500b)
        XCTAssertNotEqual(http500, http404)
        XCTAssertEqual(timeout.errorDescription, "Richiesta scaduta (timeout).")
    }

    // MARK: - 7. Delay & Status Calculations Test
    
    func testDelayAndStatusCalculations() {
        func formatDelay(delayMinutes: Int, isCancelled: Bool) -> (text: String, color: String) {
            if isCancelled {
                return ("Soppresso", "red")
            } else if delayMinutes > 0 {
                return ("Ritardo \(delayMinutes) min", "red")
            } else if delayMinutes < 0 {
                return ("Anticipo \(abs(delayMinutes)) min", "green")
            } else {
                return ("In orario", "green")
            }
        }
        
        let onTime = formatDelay(delayMinutes: 0, isCancelled: false)
        XCTAssertEqual(onTime.text, "In orario")
        XCTAssertEqual(onTime.color, "green")
        
        let late = formatDelay(delayMinutes: 12, isCancelled: false)
        XCTAssertEqual(late.text, "Ritardo 12 min")
        XCTAssertEqual(late.color, "red")
        
        let early = formatDelay(delayMinutes: -3, isCancelled: false)
        XCTAssertEqual(early.text, "Anticipo 3 min")
        XCTAssertEqual(early.color, "green")
        
        let cancelled = formatDelay(delayMinutes: 5, isCancelled: true)
        XCTAssertEqual(cancelled.text, "Soppresso")
        XCTAssertEqual(cancelled.color, "red")
    }

    // MARK: - 8. Time Calculations & Formatting Test
    
    func testTimeCalculations() {
        let t1 = TrainManager.addMinutesToTime("08:15", 45)
        XCTAssertEqual(t1, "09:00")
        
        let t2 = TrainManager.addMinutesToTime("23:50", 20)
        XCTAssertEqual(t2, "00:10")
        
        let d1 = TrainManager.calculateDurationBetween(dep: "08:15", arr: "08:45")
        XCTAssertEqual(d1, "30min")
        
        let d2 = TrainManager.calculateDurationBetween(dep: "08:15", arr: "10:30")
        XCTAssertEqual(d2, "2h 15min")
        
        let d3 = TrainManager.calculateDurationBetween(dep: "23:30", arr: "01:00")
        XCTAssertEqual(d3, "1h 30min")
    }

    // MARK: - 9. Favorites & Notification Persistence Test
    
    func testFavoritesAndNotificationPersistence() throws {
        struct SavedTrainModel: Codable, Equatable {
            let number: String
            let description: String
            var departureTime: String?
            var arrivalTime: String?
            var notifyDeparture: Bool
            var notifyDelay: Bool
        }
        
        let original = SavedTrainModel(
            number: "2461",
            description: "Milano Porta Garibaldi - Novara",
            departureTime: "07:32",
            arrivalTime: "08:14",
            notifyDeparture: true,
            notifyDelay: false
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedTrainModel.self, from: encoded)
        
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.notifyDeparture)
        XCTAssertFalse(decoded.notifyDelay)
    }

    // MARK: - 10. StationRepository Key & Cache Test
    
    func testStationRepositoryKeysAndCache() async {
        let repo = StationRepository.shared
        await repo.clearCache()
        let count = await repo.cacheCount()
        XCTAssertEqual(count, 0, "Cache should be empty after clearCache")
        
        let st1 = Station(name: "Milano Porta Venezia", rfiID: "1723", vtID: "S01649", lat: nil, lon: nil)
        let keyDep = await repo.cacheKey(for: st1, isDepartures: true)
        let keyArr = await repo.cacheKey(for: st1, isDepartures: false)
        
        XCTAssertEqual(keyDep, "S01649_true")
        XCTAssertEqual(keyArr, "S01649_false")
        
        let st2 = Station(name: "Milano Dateo", rfiID: nil, vtID: "S01650", lat: nil, lon: nil)
        let keyVT = await repo.cacheKey(for: st2, isDepartures: true)
        XCTAssertEqual(keyVT, "S01650_true")
        
        let st3 = Station(name: "Pieve Emanuele", rfiID: "1234", vtID: nil, lat: nil, lon: nil)
        let keyRFI = await repo.cacheKey(for: st3, isDepartures: true)
        XCTAssertEqual(keyRFI, "1234_true")
        
        let st4 = Station(name: "Fermata Generica", rfiID: nil, vtID: nil, lat: nil, lon: nil)
        let keyName = await repo.cacheKey(for: st4, isDepartures: false)
        XCTAssertEqual(keyName, "Fermata Generica_false")
    }

    // MARK: - 11. TrainRepository Key & Cache Test
    
    func testTrainRepositoryKeysAndCache() async {
        let repo = TrainRepository.shared
        await repo.clearCache()
        let count = await repo.cacheCount()
        XCTAssertEqual(count, 0, "Cache should be empty after clearCache")
        
        let k1 = await repo.cacheKey(trainNumber: "  2461 ", destination: " Milano Centrale ", origin: " Novara ", scheduledTime: "08:15")
        XCTAssertEqual(k1, "2461|MILANO CENTRALE|NOVARA|08:15")
        
        let k2 = await repo.cacheKey(trainNumber: "2461", destination: nil, origin: nil, scheduledTime: nil)
        XCTAssertEqual(k2, "2461|||")
    }

    // MARK: - 12. Passante Data Processing & Sanitization Test
    
    func testPassanteDataProcessingAndSanitization() {
        // 1. Message sanitization
        let raw1 = "Rischio Accodamento nel Tunnel a Venezia"
        let clean1 = PassanteManager.sanitizePassanteMessage(raw1)
        XCTAssertEqual(clean1, "Circolazione Rallentata")
        
        let raw2 = "Circolazione compromessa nel tratto Dateo-Vittoria"
        let clean2 = PassanteManager.sanitizePassanteMessage(raw2)
        XCTAssertEqual(clean2, "Circolazione fortemente rallentata Dateo-Vittoria")
        
        // 2. Train processing and delay computation
        let t1 = Train(category: "S5", number: "24501", destination: "Treviglio", time: "08:00", delay: "+5'", platform: "1")
        let t2 = Train(category: "S6", number: "24601", destination: "Pioltello", time: "08:05", delay: "In orario", platform: "2")
        let t3 = Train(category: "S5", number: "24501", destination: "Treviglio", time: "08:00", delay: "+5'", platform: "1") // Duplicate
        let t4 = Train(category: "S1", number: "24101", destination: "Lodi", time: "08:10", delay: "Soppresso", platform: "1")
        
        let venList = [t1, t2]
        let repList = [t3, t4]
        let lanList: [Train] = []
        
        let (allTrains, avgDelay) = PassanteManager.processPassanteTrains(ven: venList, rep: repList, lan: lanList)
        
        // Should deduplicate 24501: total unique trains = 3 (24501, 24601, 24101)
        XCTAssertEqual(allTrains.count, 3)
        let numbers = allTrains.map { $0.number }
        XCTAssertEqual(Set(numbers).count, 3)
        
        // Average delay: validDelays = [5, 0] (Soppresso is ignored). Avg = (5 + 0) / 2 = 2
        XCTAssertEqual(avgDelay, 2)
    }

    // MARK: - 13. NewsItem Sorting & Expired Strikes Filter Test
    
    func testNewsItemSortingAndExpiredStrikesFilter() {
        let itemFuture = NewsItem(title: "Sciopero Futuro", content: "Dettagli", isUrgent: false, category: "sciopero", date: "2099-12-31")
        let itemPast = NewsItem(title: "Sciopero Passato", content: "Dettagli", isUrgent: false, category: "sciopero", date: "2000-01-01")
        let itemInfo = NewsItem(title: "Lavori Linea", content: "Dettagli", isUrgent: false, category: "lavori", date: "2000-01-01")
        let itemUrgent = NewsItem(title: "ALLERTA", content: "Blocco totale", isUrgent: true, category: "sciopero", date: "2000-01-01")
        
        let filtered = TrainManager.filterExpiredStrikes([itemFuture, itemPast, itemInfo, itemUrgent])
        
        // itemPast should be filtered out; future, non-strike (lavori), and urgent strike should remain
        XCTAssertEqual(filtered.count, 3)
        XCTAssertTrue(filtered.contains(where: { $0.title == "Sciopero Futuro" }))
        XCTAssertTrue(filtered.contains(where: { $0.title == "Lavori Linea" }))
        XCTAssertTrue(filtered.contains(where: { $0.title == "ALLERTA" }))
        XCTAssertFalse(filtered.contains(where: { $0.title == "Sciopero Passato" }))
        
        // Test sort order: Urgent should be first
        let sorted = TrainManager.sortAndFilterNews([itemFuture, itemPast, itemInfo, itemUrgent])
        XCTAssertEqual(sorted.first?.title, "ALLERTA")
    }

    // MARK: - 14. AppLogger Control & Sanitization Test
    
    func testAppLoggerControlAndSanitization() {
        let originalState = AppLogger.isEnabled
        defer { AppLogger.setEnabled(originalState) }
        
        // 1. Test toggling logger off and on
        AppLogger.setEnabled(false)
        XCTAssertFalse(AppLogger.isEnabled, "Logger should be disabled")
        
        // Logging while disabled should execute as a no-op
        AppLogger.duration(method: "GET", endpoint: "/test", statusCode: 200, durationMs: 42)
        AppLogger.duplicateAvoided(key: "test_key")
        AppLogger.decodingError(context: "TestContext", error: AppNetworkError.invalidResponse)
        AppLogger.refreshFailed(target: "TestTarget", error: nil)
        
        AppLogger.setEnabled(true)
        XCTAssertTrue(AppLogger.isEnabled, "Logger should be enabled")
        
        // Logging while enabled should execute safely without crash
        AppLogger.duration(method: "POST", endpoint: "/reports", statusCode: 200, durationMs: 15)
        AppLogger.duplicateAvoided(key: "2461")
        AppLogger.decodingError(context: "TestContext", error: AppNetworkError.timeout)
        AppLogger.refreshFailed(target: "TestTarget", error: AppNetworkError.cancelled)
    }

    // MARK: - 15. Server Response Decoding & Errors Test
    
    func testServerResponseDecodingAndErrors() throws {
        // 1. Valid Passante Health JSON
        let validJSON = """
        {
            "healthMessage": "Circolazione Regolare",
            "healthColor": "#009640",
            "averageDelay": 3,
            "westMessage": "Ovest: Regolare",
            "westColor": "#009640",
            "eastMessage": "Est: Regolare",
            "eastColor": "#009640",
            "alerts": ["Nessun allarme"],
            "lastUpdatedTimestamp": 1700000000.0
        }
        """
        let data = try XCTUnwrap(validJSON.data(using: .utf8))
        let decoded = try PassanteManager.decodeHealthResponse(from: data)
        XCTAssertEqual(decoded.healthMessage, "Circolazione Regolare")
        XCTAssertEqual(decoded.averageDelay, 3)
        XCTAssertEqual(decoded.alerts.count, 1)
        
        // 2. Malformed JSON should throw and trigger decoding error handling
        let malformedJSON = "{\"invalid\": 123}"
        let malformedData = try XCTUnwrap(malformedJSON.data(using: .utf8))
        XCTAssertThrowsError(try PassanteManager.decodeHealthResponse(from: malformedData)) { error in
            XCTAssertTrue(error is DecodingError)
        }
        
        // 3. Comfort Reports JSON deserialization
        let comfortJSON = """
        {
            "crowded": 2,
            "hot": 1,
            "cold": 0,
            "stopped": 0,
            "blocked_locations": ["Milano Lancetti"]
        }
        """
        let comfortData = try XCTUnwrap(comfortJSON.data(using: .utf8))
        let comfortDict = try JSONSerialization.jsonObject(with: comfortData) as? [String: Any]
        XCTAssertNotNil(comfortDict)
        XCTAssertEqual(comfortDict?["crowded"] as? Int, 2)
        let blocked = comfortDict?["blocked_locations"] as? [String]
        XCTAssertEqual(blocked?.first, "Milano Lancetti")
    }

    // MARK: - 16. Stop-Specific vs Global Delay Calculation Test
    
    func testStopSpecificAndGlobalDelayCalculation() {
        let globalDelay = 10
        
        // Fermata con ritardo specifico (> 0): vince il ritardo della fermata
        let stopWithCustomDelay = 4
        let effective1 = stopWithCustomDelay > 0 ? stopWithCustomDelay : globalDelay
        XCTAssertEqual(effective1, 4, "Custom stop delay should override global delay")
        
        // Fermata senza ritardo specifico (<= 0): fallback sul ritardo globale
        let stopWithZeroDelay = 0
        let effective2 = stopWithZeroDelay > 0 ? stopWithZeroDelay : globalDelay
        XCTAssertEqual(effective2, 10, "Should fallback to global delay if stop delay is 0")
        
        // Calcolo orario stimato: 08:30 + 10 min = 08:40
        let baseTime = "08:30"
        let newTime = TrainManager.addMinutesToTime(baseTime, globalDelay)
        XCTAssertEqual(newTime, "08:40")
    }

    // MARK: - 17. Station & Notification Persistence Test
    
    func testStationAndNotificationPersistence() throws {
        // 1. Station model roundtrip
        let station = Station(
            name: "Milano Porta Garibaldi",
            rfiID: "1714",
            vtID: "S01647",
            lat: 45.484,
            lon: 9.188
        )
        let stationData = try JSONEncoder().encode(station)
        let decodedStation = try JSONDecoder().decode(Station.self, from: stationData)
        XCTAssertEqual(decodedStation.name, "Milano Porta Garibaldi")
        XCTAssertEqual(decodedStation.rfiID, "1714")
        XCTAssertEqual(decodedStation.vtID, "S01647")
        XCTAssertEqual(decodedStation.lat, 45.484)
        
        // 2. SavedTrain with multi-notification settings roundtrip
        let train = SavedTrain(
            number: "24501",
            description: "Novara - Treviglio",
            notifyDelay: true,
            notifyStationPass: true,
            stationPassName: "Milano Dateo",
            notifyDeparture: true,
            departureTime: "07:45",
            arrivalTime: "08:35",
            activeDays: [1, 2, 3, 4, 5],
            lastNotifiedPlatform: "2",
            notifyPlatformChange: true,
            platformChangeStationName: "Rho Fiera",
            lastDelayText: "In orario",
            lastDelayColorName: "green"
        )
        
        let trainData = try JSONEncoder().encode(train)
        let decodedTrain = try JSONDecoder().decode(SavedTrain.self, from: trainData)
        
        XCTAssertEqual(decodedTrain.number, "24501")
        XCTAssertEqual(decodedTrain.notifyDelay, true)
        XCTAssertEqual(decodedTrain.notifyStationPass, true)
        XCTAssertEqual(decodedTrain.stationPassName, "Milano Dateo")
        XCTAssertEqual(decodedTrain.activeDays, [1, 2, 3, 4, 5])
        XCTAssertEqual(decodedTrain.platformChangeStationName, "Rho Fiera")
    }
}
