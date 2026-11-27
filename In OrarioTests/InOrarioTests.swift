import XCTest
import Security
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
        private var releaseContinuations: [CheckedContinuation<String, Never>] = []
        private var completedResult: String?
        var executionCount = 0
        
        func executeWork() async -> String {
            executionCount += 1
            startedContinuation?.resume()
            startedContinuation = nil
            if let result = completedResult {
                return result
            }
            return await withCheckedContinuation { cont in
                self.releaseContinuations.append(cont)
            }
        }
        
        func waitForOperationStart() async {
            if executionCount > 0 { return }
            await withCheckedContinuation { cont in
                self.startedContinuation = cont
            }
        }
        
        func completeOperation(with result: String) {
            completedResult = result
            let pending = releaseContinuations
            releaseContinuations.removeAll()
            for cont in pending {
                cont.resume(returning: result)
            }
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
            
            try? await Task.sleep(nanoseconds: 50_000_000)
            
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

    @MainActor
    func testPassanteOriginTaggingAndDirectionResolution() {
        // 1. Tagging della stazione sorgente in processPassanteTrains
        let venTrain = Train(category: "S6", number: "24601", destination: "Pioltello Limito", time: "17:46", delay: "Soppresso", platform: "1")
        let repTrain = Train(category: "S5", number: "24501", destination: "Treviglio", time: "17:58", delay: "In orario", platform: "2")
        let lanTrain = Train(category: "REG", number: "24101", destination: "Bovisa", time: "17:53", delay: "Soppresso", platform: "1")
        let preTaggedTrain = Train(category: "S1", number: "24102", destination: "Lodi", time: "18:05", delay: "In orario", platform: "1", origin: "Milano Dateo")

        let (processed, _) = PassanteManager.processPassanteTrains(
            ven: [venTrain, preTaggedTrain],
            rep: [repTrain],
            lan: [lanTrain]
        )

        XCTAssertEqual(processed.first(where: { $0.number == "24601" })?.origin, "Porta Venezia")
        XCTAssertEqual(processed.first(where: { $0.number == "24501" })?.origin, "Repubblica")
        XCTAssertEqual(processed.first(where: { $0.number == "24101" })?.origin, "Lancetti")
        XCTAssertEqual(processed.first(where: { $0.number == "24102" })?.origin, "Dateo")

        // 2. Risoluzione direzione Est / Ovest
        let manager = PassanteManager()
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "REG", number: "1001", destination: "Bovisa", time: "17:53", delay: "Soppresso", platform: "1")), "Ovest")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S1", number: "24103", destination: "Saronno", time: "17:42", delay: "In orario", platform: "1")), "Ovest")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S6", number: "24603", destination: "Milano Certosa", time: "17:45", delay: "In orario", platform: "1")), "Ovest")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S6", number: "24605", destination: "Novara", time: "17:46", delay: "In orario", platform: "1")), "Ovest")

        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S5", number: "24503", destination: "Treviglio", time: "17:58", delay: "In orario", platform: "2")), "Est")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S5", number: "24505", destination: "Cassano d'Adda", time: "18:01", delay: "In orario", platform: "2")), "Est")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S6", number: "24607", destination: "Pioltello Limito", time: "17:50", delay: "+1'", platform: "2")), "Est")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "S13", number: "24301", destination: "Certosa di Pavia", time: "18:06", delay: "In orario", platform: "2")), "Est")
        XCTAssertEqual(manager.getPassanteDirection(for: Train(category: "REG", number: "1002", destination: "Lodi", time: "18:10", delay: "In orario", platform: "2")), "Est")
    }

    @MainActor
    func testPassanteLocalTunnelFetchBlockedWhenDetailClosed() async {
        let passanteManager = PassanteManager()
        let trainManager = TrainManager()

        XCTAssertFalse(passanteManager.isTunnelDetailOpen)

        let localFetched = await passanteManager.fetchAllPassanteTrains(manager: trainManager, force: true)
        XCTAssertFalse(localFetched)
        XCTAssertEqual(passanteManager.lastLocalUpdateTimestamp, 0)
        XCTAssertTrue(passanteManager.passanteTunnelTrains.isEmpty)

        let detailFetched = await passanteManager.fetchTunnelDetailData(manager: trainManager, force: true)
        XCTAssertFalse(detailFetched)
        XCTAssertFalse(passanteManager.isLocalUpdating)
        XCTAssertTrue(passanteManager.passanteTunnelTrains.isEmpty)

        passanteManager.setTunnelDetailOpen(true)
        XCTAssertTrue(passanteManager.isTunnelDetailOpen)
        passanteManager.setTunnelDetailOpen(false)
        XCTAssertFalse(passanteManager.isTunnelDetailOpen)
        XCTAssertFalse(passanteManager.isLocalUpdating)
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
            notifyScheduledTime: true,
            scheduledNotificationTime: "07:20",
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
        XCTAssertEqual(decodedTrain.notifyScheduledTime, true)
        XCTAssertEqual(decodedTrain.scheduledNotificationTime, "07:20")
    }

    func testDayCommuteScheduleCodableAndLegacyCompatibility() throws {
        // Legacy JSON senza chiavi di esclusione per giorno
        let legacyJSON = #"{"isEnabled":true,"outboundBand":"08:00 - 09:00","returnBand":"17:00 - 18:00"}"#.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(DayCommuteSchedule.self, from: legacyJSON)
        XCTAssertTrue(decodedLegacy.isEnabled)
        XCTAssertEqual(decodedLegacy.outboundBand, "08:00 - 09:00")
        XCTAssertEqual(decodedLegacy.returnBand, "17:00 - 18:00")
        XCTAssertEqual(decodedLegacy.excludedOutboundOrigins, [])
        XCTAssertEqual(decodedLegacy.excludedOutboundDestinations, [])
        XCTAssertEqual(decodedLegacy.excludedReturnOrigins, [])
        XCTAssertEqual(decodedLegacy.excludedReturnDestinations, [])
        XCTAssertFalse(decodedLegacy.hasCustomStationExclusions)

        // Round-trip completo con esclusioni personalizzate
        let custom = DayCommuteSchedule(
            isEnabled: true,
            outboundBand: "07:30 - 08:30",
            returnBand: "18:00 - 19:00",
            excludedOutboundOrigins: ["Milano Lambrate"],
            excludedOutboundDestinations: ["Trecate"],
            excludedReturnOrigins: ["Trecate"],
            excludedReturnDestinations: ["Milano Centrale"]
        )
        XCTAssertTrue(custom.hasCustomStationExclusions)

        let data = try JSONEncoder().encode(custom)
        let roundTripped = try JSONDecoder().decode(DayCommuteSchedule.self, from: data)
        XCTAssertEqual(roundTripped, custom)
        XCTAssertTrue(roundTripped.hasCustomStationExclusions)
    }

    @MainActor
    func testResolveEffectiveStationsPerDay() {
        let baseOrigins = ["Milano Centrale", "Milano Porta Garibaldi", "Rho Fiera"]
        let baseDestinations = ["Novara", "Trecate"]

        let schedule = DayCommuteSchedule(
            isEnabled: true,
            outboundBand: "08:00 - 09:00",
            returnBand: "17:00 - 18:00",
            excludedOutboundOrigins: ["Rho Fiera"],
            excludedOutboundDestinations: ["Trecate"],
            excludedReturnOrigins: ["Novara"],
            excludedReturnDestinations: ["Milano Centrale", "Rho Fiera"]
        )

        // Andata: filtra dalle liste globali
        let outbound = SupporterCommuteManager.resolveEffectiveStations(
            baseOrigins: baseOrigins,
            baseDestinations: baseDestinations,
            schedule: schedule,
            isReturn: false
        )
        XCTAssertEqual(outbound.origins, ["Milano Centrale", "Milano Porta Garibaldi"])
        XCTAssertEqual(outbound.destinations, ["Novara"])

        // Ritorno: inverte baseDestinations -> origins, baseOrigins -> destinations e applica esclusioni return
        let ret = SupporterCommuteManager.resolveEffectiveStations(
            baseOrigins: baseOrigins,
            baseDestinations: baseDestinations,
            schedule: schedule,
            isReturn: true
        )
        XCTAssertEqual(ret.origins, ["Trecate"])
        XCTAssertEqual(ret.destinations, ["Milano Porta Garibaldi"])

        // Fallback di sicurezza: se le esclusioni svuotassero completamente una lista, ritorna la lista base completa
        let excludeAllSchedule = DayCommuteSchedule(
            excludedOutboundOrigins: baseOrigins,
            excludedOutboundDestinations: baseDestinations
        )
        let fallback = SupporterCommuteManager.resolveEffectiveStations(
            baseOrigins: baseOrigins,
            baseDestinations: baseDestinations,
            schedule: excludeAllSchedule,
            isReturn: false
        )
        XCTAssertEqual(fallback.origins, baseOrigins)
        XCTAssertEqual(fallback.destinations, baseDestinations)
    }

    func testFormatCityOrStationSummaryGeneralCities() {
        XCTAssertEqual(formatCityOrStationSummary(["Bergamo", "Bergamo Ospedale"]), "Bergamo")
        XCTAssertEqual(formatCityOrStationSummary(["BERGAMO", "BERGAMO OSPEDALE"]), "Bergamo")
        XCTAssertEqual(formatCityOrStationSummary(["Milano Centrale", "Milano Porta Garibaldi"]), "Milano")
        XCTAssertEqual(formatCityOrStationSummary(["Busto Arsizio", "Busto Arsizio Nord"]), "Busto Arsizio")
        XCTAssertEqual(formatCityOrStationSummary(["Villa Raverio", "Villa Fiorita"]), "Villa Raverio, Villa Fiorita")
        XCTAssertEqual(formatCityOrStationSummary(["Milano Porta Garibaldi", "Rho Fiera"]), "Milano Porta Garibaldi, Rho Fiera")
    }

    @MainActor
    func testScheduledSummaryWeekdaysFallbackPreventsEmptyDays() {
        let mgr = SupporterCommuteManager.shared
        let prevCustom = mgr.customizePerDay
        let prevActive = mgr.activeWeekdays
        let prevExcluded = mgr.scheduledSummaryExcludedWeekdays
        defer {
            mgr.customizePerDay = prevCustom
            mgr.activeWeekdays = prevActive
            mgr.scheduledSummaryExcludedWeekdays = prevExcluded
        }

        mgr.customizePerDay = false
        mgr.activeWeekdays = [1, 2]
        mgr.scheduledSummaryExcludedWeekdays = [1, 2, 3, 4, 5]

        XCTAssertEqual(mgr.effectiveScheduledSummaryWeekdays, [1, 2])
        XCTAssertTrue(mgr.isScheduledSummaryActive(on: 1))
        XCTAssertFalse(mgr.isScheduledSummaryActive(on: 3))
    }

    @MainActor
    func testCommuteAndScheduledSummaryEntitlementGating() async {
        let mgr = SupporterCommuteManager.shared
        let defaults = UserDefaults.standard
        let hadSupportKey = defaults.object(forKey: "tip.colazionee")
        let hadSupIdKey = defaults.object(forKey: "supporter_eternal_id")
        let hadRemoteNotifKey = defaults.object(forKey: "remoteNotificationsEnabled_v1")
        let prevOrigins = mgr.origins
        let prevDests = mgr.destinations
        let prevSummaryEnabled = mgr.scheduledSummaryEnabled
        let prevProactiveEnabled = mgr.proactiveAlertsEnabled
        let prevActivePlanB = mgr.activePlanB
        let prevPinnedPlanB = mgr.pinnedPlanB

        defer {
            if let v = hadSupportKey { defaults.set(v, forKey: "tip.colazionee") } else { defaults.removeObject(forKey: "tip.colazionee") }
            if let s = hadSupIdKey { defaults.set(s, forKey: "supporter_eternal_id") } else { defaults.removeObject(forKey: "supporter_eternal_id") }
            if let n = hadRemoteNotifKey { defaults.set(n, forKey: "remoteNotificationsEnabled_v1") } else { defaults.removeObject(forKey: "remoteNotificationsEnabled_v1") }
            mgr.origins = prevOrigins
            mgr.destinations = prevDests
            mgr.scheduledSummaryEnabled = prevSummaryEnabled
            mgr.proactiveAlertsEnabled = prevProactiveEnabled
            mgr.activePlanB = prevActivePlanB
            if let p = prevPinnedPlanB { mgr.pinPlanB(p) } else { mgr.unpinPlanB() }
        }

        defaults.set("sup_test_gating", forKey: "supporter_eternal_id")
        mgr.origins = ["Milano Centrale"]
        mgr.destinations = ["Magenta"]
        mgr.scheduledSummaryEnabled = true
        mgr.proactiveAlertsEnabled = true

        // 1. Utente gratuito (anche con eventuali preferenze residue da un vecchio abbonamento)
        defaults.set(false, forKey: "tip.colazionee")
        let samplePlan = PlanBReportDTO(
            title: "Test",
            body: "Test",
            incident_type: "summary_ok",
            incident_detail: nil,
            cancelled_train: nil,
            target_time: "08:00 - 09:00",
            origins: ["Milano Centrale"],
            destinations: ["Magenta"],
            alternatives: [],
            timestamp: "2026-11-18T10:00:00"
        )
        mgr.activePlanB = samplePlan
        mgr.pinPlanB(samplePlan)

        XCTAssertFalse(mgr.hasSupport())
        XCTAssertFalse(mgr.shouldShowPromptBanner)
        let freePayload = mgr.buildCommuteSyncPayload()
        XCTAssertEqual(freePayload?["scheduled_summary_enabled"] as? Bool, false)
        XCTAssertEqual(freePayload?["proactive_alerts"] as? Bool, false)

        await mgr.handlePurchasesUpdated()
        XCTAssertNil(mgr.activePlanB)
        XCTAssertNil(mgr.pinnedPlanB)

        // 2. Utente Pro
        defaults.set(true, forKey: "tip.colazionee")
        defaults.set(true, forKey: "remoteNotificationsEnabled_v1")
        XCTAssertTrue(mgr.hasSupport())
        let proPayload = mgr.buildCommuteSyncPayload()
        XCTAssertEqual(proPayload?["scheduled_summary_enabled"] as? Bool, true)
        XCTAssertEqual(proPayload?["proactive_alerts"] as? Bool, true)

        // 3. Master switch "Abilita Notifiche" disattivato -> forza false lato server
        defaults.set(false, forKey: "remoteNotificationsEnabled_v1")
        let mutedPayload = mgr.buildCommuteSyncPayload()
        XCTAssertEqual(mutedPayload?["scheduled_summary_enabled"] as? Bool, false)
        XCTAssertEqual(mutedPayload?["proactive_alerts"] as? Bool, false)

        defaults.set(true, forKey: "remoteNotificationsEnabled_v1")
        let unmutedPayload = mgr.buildCommuteSyncPayload()
        XCTAssertEqual(unmutedPayload?["scheduled_summary_enabled"] as? Bool, true)
        XCTAssertEqual(unmutedPayload?["proactive_alerts"] as? Bool, true)
    }

    @MainActor
    func testSupporterUpdatePopupSuppressionAndMetroBetaDefault() {
        let defaults = UserDefaults.standard
        let updater = AppUpdateManager.shared
        let commute = SupporterCommuteManager.shared

        let prevOrigins = commute.origins
        let prevDests = commute.destinations
        let prevLaunched = defaults.object(forKey: "has_launched_before_key")
        let prevLastSeen = defaults.object(forKey: "supporter_last_seen_version")
        let prevSnoozed = defaults.object(forKey: "supporter_commute_alert_snoozed_until")
        let prevShowAlert = updater.showSupporterCommuteAlert
        let prevChecked = updater.hasCheckedSupporterPopupThisLaunch
        let prevMetroBeta = defaults.object(forKey: "metroMilanoBetaEnabled")

        defer {
            commute.origins = prevOrigins
            commute.destinations = prevDests
            if let v = prevLaunched { defaults.set(v, forKey: "has_launched_before_key") } else { defaults.removeObject(forKey: "has_launched_before_key") }
            if let v = prevLastSeen { defaults.set(v, forKey: "supporter_last_seen_version") } else { defaults.removeObject(forKey: "supporter_last_seen_version") }
            if let v = prevSnoozed { defaults.set(v, forKey: "supporter_commute_alert_snoozed_until") } else { defaults.removeObject(forKey: "supporter_commute_alert_snoozed_until") }
            updater.showSupporterCommuteAlert = prevShowAlert
            updater.hasCheckedSupporterPopupThisLaunch = prevChecked
            if let v = prevMetroBeta { defaults.set(v, forKey: "metroMilanoBetaEnabled") } else { defaults.removeObject(forKey: "metroMilanoBetaEnabled") }
        }

        // 1. Se l'utente ha già configurato le stazioni di viaggio, il popup NON deve comparire nemmeno su update major/minor
        defaults.set(true, forKey: "has_launched_before_key")
        defaults.set("1.0", forKey: "supporter_last_seen_version")
        defaults.removeObject(forKey: "supporter_commute_alert_snoozed_until")
        updater.showSupporterCommuteAlert = false
        updater.hasCheckedSupporterPopupThisLaunch = false
        commute.origins = ["Magenta"]
        commute.destinations = ["Milano Centrale"]

        updater.checkSupporterUpdatePopup(hasSupport: true)
        XCTAssertFalse(updater.showSupporterCommuteAlert)

        // 2. Se non configurato ma l'utente ha premuto "Ricordamelo più tardi", lo snooze blocca ricomparse immediate
        commute.origins = []
        commute.destinations = []
        defaults.set("1.0", forKey: "supporter_last_seen_version")
        updater.hasCheckedSupporterPopupThisLaunch = false
        updater.checkSupporterUpdatePopup(hasSupport: true)
        XCTAssertTrue(updater.showSupporterCommuteAlert)

        updater.snoozeSupporterCommuteAlert()
        XCTAssertFalse(updater.showSupporterCommuteAlert)

        updater.hasCheckedSupporterPopupThisLaunch = false
        updater.checkSupporterUpdatePopup(hasSupport: true)
        XCTAssertFalse(updater.showSupporterCommuteAlert)

        // 3. Metro Milano Beta è disattivata di default se non esplicitamente impostata dall'utente
        defaults.removeObject(forKey: "metroMilanoBetaEnabled")
        XCTAssertFalse(defaults.bool(forKey: "metroMilanoBetaEnabled"))
    }

    @MainActor
    func testDeviceIdentityManagerStabilityAndCommutePayload() {
        let suiteName = "com.toreroclub.inorario.tests.deviceid.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        let testService = "com.toreroclub.inorario.test.service.\(UUID().uuidString)"
        let testAccount = "test_account"
        let testFallbackKey = "test_fallback_key"

        let mgr = SupporterCommuteManager.shared
        let defaults = UserDefaults.standard
        let hadSupId = defaults.object(forKey: "supporter_eternal_id")
        let prevOrigins = mgr.origins
        let prevDests = mgr.destinations

        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
            let secQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: testService,
                kSecAttrAccount as String: testAccount
            ]
            SecItemDelete(secQuery as CFDictionary)
            if let s = hadSupId { defaults.set(s, forKey: "supporter_eternal_id") } else { defaults.removeObject(forKey: "supporter_eternal_id") }
            mgr.origins = prevOrigins
            mgr.destinations = prevDests
        }

        let idManager1 = DeviceIdentityManager(
            service: testService,
            account: testAccount,
            defaults: testDefaults,
            fallbackDefaultsKey: testFallbackKey
        )
        let firstID = idManager1.deviceID
        XCTAssertFalse(firstID.isEmpty)
        XCTAssertNotNil(UUID(uuidString: firstID))
        XCTAssertEqual(idManager1.deviceID, firstID)

        let idManager2 = DeviceIdentityManager(
            service: testService,
            account: testAccount,
            defaults: testDefaults,
            fallbackDefaultsKey: testFallbackKey
        )
        XCTAssertEqual(idManager2.deviceID, firstID)

        defaults.set("sup_test_device_id", forKey: "supporter_eternal_id")
        mgr.origins = ["Magenta"]
        mgr.destinations = ["Milano Centrale"]
        let payload = mgr.buildCommuteSyncPayload()
        XCTAssertEqual(payload?["device_id"] as? String, DeviceIdentityManager.shared.deviceID)
    }

    @MainActor
    func testSmartQueryRoutingLocalExactAndDateResolution() async {
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: true, hasAppleIntelligence: true), .geminiCloud)
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: true, hasAppleIntelligence: false), .geminiCloud)
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: false, hasAppleIntelligence: true), .appleIntelligence)
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: false, hasAppleIntelligence: false), .localExactOnly)
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: true, hasAppleIntelligence: true, aiModeChoice: .local), .appleIntelligence)
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: true, hasAppleIntelligence: true, aiModeChoice: .cloud), .geminiCloud)
        XCTAssertEqual(SmartQueryEnginePolicy.resolve(hasSupport: true, hasAppleIntelligence: true, aiModeChoice: .none), .localExactOnly)
        XCTAssertEqual(AIFeatureManager.defaultAIMode(hasSupport: true, hasAppleIntelligence: true), .cloud)
        XCTAssertEqual(AIFeatureManager.defaultAIMode(hasSupport: true, hasAppleIntelligence: false), .cloud)
        XCTAssertEqual(AIFeatureManager.defaultAIMode(hasSupport: false, hasAppleIntelligence: true), .local)
        XCTAssertEqual(AIFeatureManager.defaultAIMode(hasSupport: false, hasAppleIntelligence: false), .none)
        XCTAssertEqual(LocalExactQueryParser.applyKnownAlias("Torino"), "Torino Porta Nuova")
        XCTAssertEqual(LocalExactQueryParser.applyKnownAlias("Rho Fiera"), "Rho Fiera")
        XCTAssertEqual(LocalExactQueryParser.applyKnownAlias("Milano Repubblica"), "Milano Repubblica")
        XCTAssertEqual(LocalExactQueryParser.applyKnownAlias("maggenta"), "Magenta")
        XCTAssertEqual(LocalExactQueryParser.applyKnownAlias("milano porta garibaldi"), "Milano Porta Garibaldi")

        let mgr = TrainManager()
        let prevRecent = mgr.recentAssistantQueries
        mgr.clearRecentAssistantQueries()
        mgr.addRecentAssistantQuery("Partenze Milano Rogoredo")
        mgr.addRecentAssistantQuery("Treno delle 11:34 da Magenta")
        mgr.addRecentAssistantQuery("partenze milano rogoredo")
        XCTAssertEqual(mgr.recentAssistantQueries.first, "partenze milano rogoredo")
        XCTAssertEqual(mgr.recentAssistantQueries.count, 2)
        mgr.removeRecentAssistantQuery("partenze milano rogoredo")
        XCTAssertEqual(mgr.recentAssistantQueries, ["Treno delle 11:34 da Magenta"])
        mgr.clearRecentAssistantQueries()
        for q in prevRecent.reversed() {
            mgr.addRecentAssistantQuery(q)
        }

        let stations = [
            RFIStation(name: "Magenta", rfiID: "830001025", vtID: "S01025", lat: 45.465, lon: 8.882),
            RFIStation(name: "MILANO AFFORI", rfiID: "830025005", vtID: "S01078", lat: 45.512, lon: 9.168),
            RFIStation(name: "Milano Centrale", rfiID: "830001700", vtID: "S01700", lat: 45.485, lon: 9.204),
            RFIStation(name: "Milano Nord Cadorna", rfiID: nil, vtID: "N00001", lat: 45.468, lon: 9.176),
            RFIStation(name: "Milano Porta Garibaldi", rfiID: "830001645", vtID: "S01645", lat: 45.484, lon: 9.187),
            RFIStation(name: "VITTUONE-ARLUNO", rfiID: "830001036", vtID: "S01036", lat: 45.486, lon: 8.953),
            RFIStation(name: "CORBETTA-S.STEFANO TICINO", rfiID: "830001038", vtID: "S01038", lat: 45.474, lon: 8.920),
            RFIStation(name: "NOVARA", rfiID: "830000247", vtID: "S00247", lat: 45.451, lon: 8.625),
            RFIStation(name: "DOMODOSSOLA", rfiID: "830000202", vtID: "S00202", lat: 46.115, lon: 8.296)
        ]

        var romeCal = Calendar(identifier: .gregorian)
        let romeTZ = TimeZone(identifier: "Europe/Rome")!
        romeCal.timeZone = romeTZ
        let nowRef = romeCal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 10, minute: 15))!

        // 1. Numero treno esatto
        let qTrain = LocalExactQueryParser.parse(query: "S6 24627", knownStations: stations)
        XCTAssertEqual(qTrain?.kind, .trainStatus)
        XCTAssertEqual(qTrain?.trainNumber, "24627")

        // 2. Orario esatto da stazione
        let qTimeStation = LocalExactQueryParser.parse(query: "Treno delle 11:34 da Magenta", knownStations: stations)
        XCTAssertEqual(qTimeStation?.kind, .trainAtTimeFromStation)
        XCTAssertEqual(qTimeStation?.originStation, "Magenta")
        XCTAssertEqual(qTimeStation?.targetTime, "11:34")

        // 3. Primo treno da A a B (banale esatto con stazioni note / alias)
        let qRoute = LocalExactQueryParser.parse(query: "Primo treno da Magenta a Centrale", knownStations: stations)
        XCTAssertEqual(qRoute?.kind, .routeSolutions)
        XCTAssertEqual(qRoute?.originStation, "Magenta")
        XCTAssertEqual(qRoute?.destinationStation, "Milano Centrale")

        // 4. Layer 1 locale addestrato sulle 6 query reali dell'utente e pattern vocali umani
        let qComplex = LocalExactQueryParser.parse(
            query: "Voglio andare da Milano Cadorna a Magenta alle 16 di domani",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qComplex?.kind, .routeSolutions)
        XCTAssertEqual(qComplex?.originStation, "Milano Nord Cadorna")
        XCTAssertEqual(qComplex?.destinationStation, "Magenta")
        XCTAssertEqual(qComplex?.targetDate, "2026-11-22")
        XCTAssertEqual(qComplex?.targetTime, "16:00")

        let qPomeriggio = LocalExactQueryParser.parse(
            query: "portami a magenta da milano centrale oggi pomeriggio",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qPomeriggio?.kind, .routeSolutions)
        XCTAssertEqual(qPomeriggio?.originStation, "Milano Centrale")
        XCTAssertEqual(qPomeriggio?.destinationStation, "Magenta")
        XCTAssertEqual(qPomeriggio?.targetDate, "2026-11-21")
        XCTAssertEqual(qPomeriggio?.targetTime, "14:30")

        let qCasa = LocalExactQueryParser.parse(
            query: "portami a casa da milano centrale",
            knownStations: stations,
            homeStations: ["Magenta"],
            workStations: ["Milano Centrale", "Milano Porta Garibaldi"],
            now: nowRef
        )
        XCTAssertEqual(qCasa?.kind, .routeSolutions)
        XCTAssertEqual(qCasa?.originStation, "Milano Centrale")
        XCTAssertEqual(qCasa?.destinationStation, "Magenta")

        let qMagGaribaldi = LocalExactQueryParser.parse(
            query: "Treno delle 18:19 da Magenta a Milano porta garibaldi",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qMagGaribaldi?.kind, .routeSolutions)
        XCTAssertEqual(qMagGaribaldi?.originStation, "Magenta")
        XCTAssertEqual(qMagGaribaldi?.destinationStation, "Milano Porta Garibaldi")
        XCTAssertEqual(qMagGaribaldi?.targetTime, "18:19")

        let qMagMi = LocalExactQueryParser.parse(
            query: "Treno delle 18:20 da Magenta a Milano",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qMagMi?.kind, .routeSolutions)
        XCTAssertEqual(qMagMi?.originStation, "Magenta")
        XCTAssertEqual(qMagMi?.destinationStation, "Milano")
        XCTAssertEqual(qMagMi?.targetTime, "18:20")

        let qNovara = LocalExactQueryParser.parse(
            query: "NOVARA Domodossola domani alle 12",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qNovara?.kind, .routeSolutions)
        XCTAssertEqual(qNovara?.originStation, "NOVARA")
        XCTAssertEqual(qNovara?.destinationStation, "DOMODOSSOLA")
        XCTAssertEqual(qNovara?.targetDate, "2026-11-22")
        XCTAssertEqual(qNovara?.targetTime, "12:00")

        // Pattern vocali naturali, frasi disordinate, autocorrezioni e trascrizione parlata
        XCTAssertEqual(VoiceTranscriptCleaner.normalize("porta mi a casa da milano centrale alle 18 e 19"), "portami a casa da milano centrale alle 18:19")
        XCTAssertEqual(SmartQueryPostProcessor.extractExplicitTime(from: "treno delle 18 e 19", now: nowRef), "18:19")
        XCTAssertEqual(SmartQueryPostProcessor.extractExplicitTime(from: "domani alle 8 e mezza", now: nowRef), "08:30")
        XCTAssertEqual(SmartQueryPostProcessor.extractExplicitTime(from: "alle 4 del pomeriggio", now: nowRef), "16:00")
        XCTAssertEqual(SmartQueryPostProcessor.extractExplicitTime(from: "treno da Magenta a Milano domani a partire dalle 18:00", now: nowRef), "18:00")
        XCTAssertEqual(SmartQueryPostProcessor.extractExplicitTime(from: "treno da Magenta a Milano domani a partire dalle 18", now: nowRef), "18:00")
        XCTAssertEqual(SmartQueryPostProcessor.extractExplicitTime(from: "da Magenta a Milano domani dalle 18 e 30", now: nowRef), "18:30")

        let qFrom18WithColon = LocalExactQueryParser.parse(query: "treno da Magenta a Milano domani a partire dalle 18:00", knownStations: stations, now: nowRef)
        XCTAssertEqual(qFrom18WithColon?.kind, .routeSolutions)
        XCTAssertEqual(qFrom18WithColon?.originStation, "Magenta")
        XCTAssertEqual(qFrom18WithColon?.destinationStation, "Milano")
        XCTAssertEqual(qFrom18WithColon?.targetDate, "2026-11-22")
        XCTAssertEqual(qFrom18WithColon?.targetTime, "18:00")

        let qFrom18Bare = LocalExactQueryParser.parse(query: "treno da Magenta a Milano domani a partire dalle 18", knownStations: stations, now: nowRef)
        XCTAssertEqual(qFrom18Bare?.kind, .routeSolutions)
        XCTAssertEqual(qFrom18Bare?.originStation, "Magenta")
        XCTAssertEqual(qFrom18Bare?.destinationStation, "Milano")
        XCTAssertEqual(qFrom18Bare?.targetDate, "2026-11-22")
        XCTAssertEqual(qFrom18Bare?.targetTime, "18:00")

        let qStartTime = LocalExactQueryParser.parse(query: "domani mattina alle 8 da Magenta a Milano", knownStations: stations, now: nowRef)
        XCTAssertEqual(qStartTime?.kind, .routeSolutions)
        XCTAssertEqual(qStartTime?.originStation, "Magenta")
        XCTAssertEqual(qStartTime?.destinationStation, "Milano")
        XCTAssertEqual(qStartTime?.targetDate, "2026-11-22")
        XCTAssertEqual(qStartTime?.targetTime, "08:00")

        let qMidTime = LocalExactQueryParser.parse(query: "da Magenta domani pomeriggio alle 4 per Milano Porta Garibaldi", knownStations: stations, now: nowRef)
        XCTAssertEqual(qMidTime?.kind, .routeSolutions)
        XCTAssertEqual(qMidTime?.originStation, "Magenta")
        XCTAssertEqual(qMidTime?.destinationStation, "Milano Porta Garibaldi")
        XCTAssertEqual(qMidTime?.targetDate, "2026-11-22")
        XCTAssertEqual(qMidTime?.targetTime, "16:00")

        let qSonoACasa = LocalExactQueryParser.parse(
            query: "sono a Milano Centrale e devo tornare a casa",
            knownStations: stations,
            homeStations: ["Magenta"],
            workStations: ["Milano Centrale"],
            now: nowRef
        )
        XCTAssertEqual(qSonoACasa?.kind, .routeSolutions)
        XCTAssertEqual(qSonoACasa?.originStation, "Milano Centrale")
        XCTAssertEqual(qSonoACasa?.destinationStation, "Magenta")

        let qAnziNo = LocalExactQueryParser.parse(
            query: "voglio andare a Milano Centrale anzi no Porta Garibaldi da Magenta",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qAnziNo?.kind, .routeSolutions)
        XCTAssertEqual(qAnziNo?.originStation, "Magenta")
        XCTAssertEqual(qAnziNo?.destinationStation, "Milano Porta Garibaldi")

        let qCasaLavoro = LocalExactQueryParser.parse(
            query: "parto da casa domani alle 7 e mezza e vado al lavoro",
            knownStations: stations,
            homeStations: ["Magenta"],
            workStations: ["Milano Centrale"],
            now: nowRef
        )
        XCTAssertEqual(qCasaLavoro?.kind, .routeSolutions)
        XCTAssertEqual(qCasaLavoro?.originStation, "Magenta")
        XCTAssertEqual(qCasaLavoro?.destinationStation, "Milano Centrale")
        XCTAssertEqual(qCasaLavoro?.targetDate, "2026-11-22")
        XCTAssertEqual(qCasaLavoro?.targetTime, "07:30")

        let qEscoLavoro = LocalExactQueryParser.parse(
            query: "esco da lavoro alle 18",
            knownStations: stations,
            homeStations: ["Magenta"],
            workStations: ["Milano Centrale"],
            now: nowRef
        )
        XCTAssertEqual(qEscoLavoro?.kind, .routeSolutions)
        XCTAssertEqual(qEscoLavoro?.originStation, "Milano Centrale")
        XCTAssertEqual(qEscoLavoro?.destinationStation, "Magenta")
        XCTAssertEqual(qEscoLavoro?.targetTime, "18:00")

        let qDeadline = LocalExactQueryParser.parse(
            query: "devo essere a Milano Centrale alle 9 da Magenta",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qDeadline?.kind, .routeSolutions)
        XCTAssertEqual(qDeadline?.originStation, "Magenta")
        XCTAssertEqual(qDeadline?.destinationStation, "Milano Centrale")
        XCTAssertEqual(qDeadline?.targetTime, "08:10")

        let qBare1820 = LocalExactQueryParser.parse(
            query: "Magenta Milano delle 18 e 20",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qBare1820?.kind, .routeSolutions)
        XCTAssertEqual(qBare1820?.originStation, "Magenta")
        XCTAssertEqual(qBare1820?.destinationStation, "Milano")
        XCTAssertEqual(qBare1820?.targetTime, "18:20")

        let qHyphenPranzo = LocalExactQueryParser.parse(
            query: "treno da vittuone a corbetta dopo pranzo",
            knownStations: stations,
            now: nowRef
        )
        XCTAssertEqual(qHyphenPranzo?.kind, .routeSolutions)
        XCTAssertEqual(qHyphenPranzo?.originStation, "VITTUONE-ARLUNO")
        XCTAssertEqual(qHyphenPranzo?.destinationStation, "CORBETTA-S.STEFANO TICINO")
        XCTAssertEqual(qHyphenPranzo?.targetTime, "14:00")

        // Risoluzione "Milano" su tratta NON deve MAI selezionare "MILANO AFFORI"
        let resolvedMilanoRoute = await SmartQueryExecutor.shared.resolveStation(
            name: "Milano",
            allStations: stations,
            fallbackNearby: nil,
            forRouteSearch: true
        )
        XCTAssertEqual(resolvedMilanoRoute?.name, "Milano")
        XCTAssertEqual(resolvedMilanoRoute?.rfiID, "830001650")
        XCTAssertNotEqual(resolvedMilanoRoute?.name.uppercased(), "MILANO AFFORI")

        // 5. Risoluzione data/ora in Europe/Rome
        let parsedRoute = SmartTrainQuery(
            kind: .routeSolutions,
            originStation: "Milano Cadorna",
            destinationStation: "Magenta",
            targetDate: "2026-11-20",
            targetTime: "16:00"
        )
        let resolved = parsedRoute.resolvedDate(now: nowRef)
        let comps = romeCal.dateComponents([.year, .month, .day, .hour, .minute], from: resolved)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 16)
        XCTAssertEqual(comps.minute, 0)

        // 6. Guardrail SmartQueryPostProcessor (orario esplicito preservato + GPS "Portami a ..." + summary non vuoto)
        let badTimeModelOut = SmartTrainQuery(
            kind: .trainAtTimeFromStation,
            originStation: "Magenta",
            destinationStation: nil,
            targetDate: "2026-11-19",
            targetTime: "21:34",
            normalizedSummary: "",
            engineUsed: "apple_intelligence"
        )
        let refinedTime = SmartQueryPostProcessor.refine(
            parsed: badTimeModelOut,
            rawQuery: "Treno delle 11:34 da Magenta",
            nearbyStation: nil,
            now: nowRef
        )
        XCTAssertEqual(refinedTime.targetTime, "11:34")
        XCTAssertEqual(refinedTime.displaySummary(fallbackQuery: "Treno delle 11:34 da Magenta"), "Treno delle 11:34 da Magenta")

        let portamiModelOut = SmartTrainQuery(
            kind: .routeSolutions,
            originStation: "nessuna",
            destinationStation: nil,
            targetDate: nil,
            targetTime: "16:00",
            normalizedSummary: nil,
            engineUsed: "apple_intelligence"
        )
        let refinedPortami = SmartQueryPostProcessor.refine(
            parsed: portamiModelOut,
            rawQuery: "Portami a Milano Porta Garibaldi alle 16:00 di domani",
            nearbyStation: "Magenta",
            now: nowRef
        )
        XCTAssertEqual(refinedPortami.kind, .routeSolutions)
        XCTAssertEqual(refinedPortami.originStation, "Magenta")
        XCTAssertEqual(refinedPortami.destinationStation, "Milano Porta Garibaldi")
        XCTAssertEqual(refinedPortami.targetDate, "2026-11-22")
        XCTAssertEqual(refinedPortami.targetTime, "16:00")
        XCTAssertFalse(refinedPortami.displaySummary(fallbackQuery: "").isEmpty)

        // 7. SmartQueryExecutor.matchTrainInList NON deve mai restituire treni di un altro orario (es. 21:34/21:41 quando si cerca 11:34)
        let eveningBoard = [
            Train(category: "S6", number: "24685", destination: "Pioltello Limito", time: "21:34", delay: "In orario", platform: "2"),
            Train(category: "RV", number: "2045", destination: "Milano Centrale", time: "21:41", delay: "In orario", platform: "2")
        ]
        XCTAssertNil(SmartQueryExecutor.shared.matchTrainInList(eveningBoard, requestedHHmm: "11:34", destinationHint: nil))

        let morningBoard = [
            Train(category: "S6", number: "24635", destination: "Milano Porta Garibaldi", time: "11:34", delay: "In orario", platform: "2"),
            Train(category: "RV", number: "2023", destination: "Milano Centrale", time: "11:49", delay: "In orario", platform: "2")
        ]
        let matchedMorning = SmartQueryExecutor.shared.matchTrainInList(morningBoard, requestedHHmm: "11:34", destinationHint: nil)
        XCTAssertEqual(matchedMorning?.number, "24635")
        XCTAssertEqual(matchedMorning?.time, "11:34")
    }

    // MARK: - 14. Station Board Filters, Commute Matcher & History Success Check

    func testTrainCategoryClassificationAndSuburbanLines() {
        let trains: [(String, String, TrainCategoryGroup, String?)] = [
            ("FR", "9614", .highSpeed, nil),
            ("FA", "8502", .highSpeed, nil),
            ("FB", "8610", .highSpeed, nil),
            ("AV", "9511", .highSpeed, nil),
            ("Italo", "9912", .highSpeed, nil),
            ("IC", "660", .intercity, nil),
            ("ICN", "754", .intercity, nil),
            ("EC", "310", .intercity, nil),
            ("REG", "25871", .regional, nil),
            ("RV", "2023", .regional, nil),
            ("RE", "2969", .regional, nil),
            ("S5", "24566", .suburban, "S5"),
            ("S13", "24467", .suburban, "S13"),
            ("MXP", "312", .airport, nil),
        ]

        for (cat, num, expectedGroup, expectedSub) in trains {
            let tr = Train(category: cat, number: num, destination: "Milano", time: "10:00", delay: "In orario", platform: "1")
            XCTAssertEqual(TrainCategoryGroup.classify(tr), expectedGroup, "Failed group for \(cat) \(num)")
            XCTAssertEqual(TrainCategoryGroup.suburbanLineCode(for: tr), expectedSub, "Failed suburban code for \(cat) \(num)")
        }
    }

    func testStationBoardFilterCombinations() {
        let board = [
            Train(category: "S13", number: "24467", destination: "Pavia", time: "19:33", delay: "+1'", platform: "1 SOT"),
            Train(category: "RE", number: "2969", destination: "Milano Centrale", time: "19:26", delay: "+12'", platform: "--"),
            Train(category: "REG", number: "25871", destination: "Ponte S. Pietro", time: "19:31", delay: "In orario", platform: "17"),
            Train(category: "S5", number: "24566", destination: "Varese", time: "19:34", delay: "Cancellato", platform: "2 SOT"),
            Train(category: "FR", number: "9614", destination: "Torino P.N.", time: "19:40", delay: "In orario", platform: "5"),
        ]

        var state = StationBoardFilterState()
        state.hideCancelled = true
        state.onlyWithPlatform = true
        let activeBoards = state.apply(to: board, favoriteTrainNumbers: ["24467"], commuteMatches: nil)
        XCTAssertEqual(activeBoards.map(\.number), ["24467", "25871", "9614"])

        state.onlyOnTime = true
        let onTimeWithPlat = state.apply(to: board, favoriteTrainNumbers: ["24467"], commuteMatches: nil)
        XCTAssertEqual(onTimeWithPlat.map(\.number), ["25871", "9614"])

        var subFilter = StationBoardFilterState()
        subFilter.selectedSuburbanLines = ["S13"]
        subFilter.selectedCategories = [.regional]
        let mixed = subFilter.apply(to: board, favoriteTrainNumbers: [], commuteMatches: nil)
        XCTAssertEqual(mixed.map(\.number), ["24467", "2969", "25871"])

        var favFilter = StationBoardFilterState()
        favFilter.onlyFavorites = true
        let favOnly = favFilter.apply(to: board, favoriteTrainNumbers: ["24467"], commuteMatches: nil)
        XCTAssertEqual(favOnly.map(\.number), ["24467"])

        var commuteFilter = StationBoardFilterState()
        commuteFilter.commuteTarget = .home
        let matches: [String: CommuteTrainMatch] = [
            "25871": CommuteTrainMatch(trainNumber: "25871", matchedTargetStation: "Magenta", estimatedArrivalTime: "20:02", source: .lefrecce)
        ]
        let commuteFiltered = commuteFilter.apply(to: board, favoriteTrainNumbers: [], commuteMatches: matches)
        XCTAssertEqual(commuteFiltered.map(\.number), ["25871"])
    }

    func testStationNameMatcherAndOrderedStops() {
        XCTAssertTrue(StationNameMatcher.isSameStation("Milano Porta Garibaldi", "Milano P. Garibaldi"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Milano P. Garibaldi Passante", "Milano Porta Garibaldi Sotterranea"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Milano Porta Garibaldi", "Pavia Porta Garibaldi"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Milano Certosa", "Certosa di Pavia"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Milano Bovisa Politecnico", "Milano Bovisa"))

        let stops = [
            Stop(stationName: "Torino Porta Nuova", time: "17:00", actualTime: "17:00", delay: 0, estimatedTime: nil, plannedPlatform: "1", actualPlatform: "1"),
            Stop(stationName: "Novara", time: "17:55", actualTime: nil, delay: 0, estimatedTime: nil, plannedPlatform: "2", actualPlatform: nil),
            Stop(stationName: "Magenta", time: "18:10", actualTime: nil, delay: 0, estimatedTime: nil, plannedPlatform: "1", actualPlatform: nil),
            Stop(stationName: "Milano Porta Garibaldi", time: "18:35", actualTime: nil, delay: 0, estimatedTime: nil, plannedPlatform: "8", actualPlatform: nil),
        ]

        let forward = StationNameMatcher.stopsContainOrderedRoute(stops: stops, originStationName: "Novara", targetStations: ["Magenta"])
        XCTAssertEqual(forward?.targetStation, "Magenta")
        XCTAssertEqual(forward?.arrivalTime, "18:10")

        // Direzione opposta: Magenta viene prima di Milano Porta Garibaldi
        let reverse = StationNameMatcher.stopsContainOrderedRoute(stops: stops, originStationName: "Milano P. Garibaldi", targetStations: ["Magenta"])
        XCTAssertNil(reverse)
    }

    func testSmartQueryExecutionResultSuccessForHistory() {
        let station = Station(name: "Magenta", rfiID: "1618", vtID: "S01040")
        let dummyTrain = Train(category: "S6", number: "24652", destination: "Milano", time: "18:19", delay: "In orario", platform: "2")

        XCTAssertFalse(SmartQueryExecutionResult.message("Errore").isSuccessfulForHistory)
        XCTAssertFalse(SmartQueryExecutionResult.solutions(solutions: [], origin: "Magenta", destination: "Milano", originID: "1", destID: "2", searchDate: Date()).isSuccessfulForHistory)
        XCTAssertFalse(SmartQueryExecutionResult.trainAtTime(train: nil, station: station, boardSample: [], requestedTime: "18:19").isSuccessfulForHistory)

        XCTAssertTrue(SmartQueryExecutionResult.trainStatus(train: dummyTrain).isSuccessfulForHistory)
        XCTAssertTrue(SmartQueryExecutionResult.stationBoard(station: station, isArrivals: false).isSuccessfulForHistory)
        XCTAssertTrue(SmartQueryExecutionResult.trainAtTime(train: dummyTrain, station: station, boardSample: [dummyTrain], requestedTime: "18:19").isSuccessfulForHistory)
    }

    func testStage0OnlyMatchesExactTerminus() {
        let board = [
            Train(category: "FR", number: "9614", destination: "Novara", time: "18:10", delay: "In orario", platform: "4"),
            Train(category: "S6", number: "24652", destination: "Novara", time: "18:19", delay: "In orario", platform: "2 SOT"),
            Train(category: "S6", number: "24654", destination: "Magenta", time: "18:49", delay: "In orario", platform: "2 SOT"),
        ]
        // Stage 0 non deve indovinare fermate intermedie senza verifica orari/fermate reali
        let matchesInterm = StationCommuteMatcher.computeStage0Matches(
            boardTrains: board,
            targetStations: ["Corbetta-S.Stefano Ticino"]
        )
        XCTAssertNil(matchesInterm["9614"])
        XCTAssertNil(matchesInterm["24652"])

        let matchesTerminus = StationCommuteMatcher.computeStage0Matches(
            boardTrains: board,
            targetStations: ["Magenta"]
        )
        XCTAssertEqual(matchesTerminus["24654"]?.matchedTargetStation, "Magenta")
        XCTAssertNil(matchesTerminus["24652"])
    }

    func testNationalStationNameMatcherAndNoFalsePositives() {
        // Alias ufficiali in tutta Italia
        XCTAssertTrue(StationNameMatcher.isSameStation("Firenze S.M.N.", "Firenze Santa Maria Novella"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Venezia S.L.", "Venezia Santa Lucia"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Torino P.N.", "Torino Porta Nuova"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Torino P.S.", "Torino Porta Susa"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Verona P.N.", "Verona Porta Nuova"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Genova P.P.", "Genova Piazza Principe"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Roma Term.", "Roma Termini"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Roma S. Pietro", "Roma San Pietro"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Bologna Centrale AV", "Bologna Centrale"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Bologna C.le", "Bologna Centrale"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Forli'", "Forlì"))
        XCTAssertTrue(StationNameMatcher.isSameStation("Milano Nord Cadorna", "Milano Cadorna"))

        // Zero falsi positivi su stazioni vicine/omonime
        XCTAssertFalse(StationNameMatcher.isSameStation("Varese", "Varese Nord"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Busto Arsizio", "Busto Arsizio Nord"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Novara", "Novara Nord"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Monza", "Monza Sobborghi"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Venezia Santa Lucia", "Venezia Mestre"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Torino Porta Nuova", "Torino Porta Susa"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Roma Termini", "Roma Tiburtina"))
        XCTAssertFalse(StationNameMatcher.isSameStation("Reggio Emilia", "Reggio Emilia AV Mediopadana"))

        // Scarta "Tutte Le Stazioni" su LeFrecce
        let genericRoma = TrenitaliaLocation(id: 830008400, name: "Roma ( Tutte Le Stazioni )", displayName: "Roma ( Tutte Le Stazioni )")
        let specificRoma = TrenitaliaLocation(id: 830008409, name: "Roma Termini", displayName: "Roma Termini")
        XCTAssertFalse(StationNameMatcher.matchesLefrecceLocation(genericRoma, targetStationName: "Roma Termini"))
        XCTAssertTrue(StationNameMatcher.matchesLefrecceLocation(specificRoma, targetStationName: "Roma Termini"))
    }

    func testLefrecceStrictDirectValidationAndSuppressedStops() throws {
        let jsonObj: [String: Any] = [
            "solutions": [
                // 1. Soluzione multi-nodo con tratto urbano/metro: deve essere SCARTATA
                [
                    "solution": [
                        "origin": "Magenta",
                        "destination": "Milano Cadorna",
                        "arrivalTime": "2026-11-21T08:40:00.000+01:00",
                        "nodes": [
                            [
                                "origin": "Magenta",
                                "destination": "Milano Porta Garibaldi",
                                "arrivalTime": "2026-11-21T08:25:00.000+01:00",
                                "train": ["name": "24612", "acronym": "S6", "urban": false]
                            ],
                            [
                                "origin": "Milano Porta Garibaldi",
                                "destination": "Milano Cadorna",
                                "arrivalTime": "2026-11-21T08:40:00.000+01:00",
                                "train": ["name": "UB", "acronym": "UB", "urban": true]
                            ]
                        ]
                    ]
                ],
                // 2. Soluzione diretta ma da stazione di partenza diversa (Milano Centrale invece di Roma Termini): SCARTATA
                [
                    "solution": [
                        "origin": "Roma Tiburtina",
                        "destination": "Firenze Santa Maria Novella",
                        "arrivalTime": "2026-11-21T10:15:00.000+01:00",
                        "nodes": [
                            [
                                "origin": "Roma Tiburtina",
                                "destination": "Firenze Santa Maria Novella",
                                "arrivalTime": "2026-11-21T10:15:00.000+01:00",
                                "train": ["name": "FR 9514", "acronym": "FR", "urban": false]
                            ]
                        ]
                    ]
                ],
                // 3. Soluzione diretta valida da Roma Termini a Firenze S.M.N.
                [
                    "solution": [
                        "origin": "Roma Termini",
                        "destination": "Firenze Santa Maria Novella",
                        "arrivalTime": "2026-11-21T10:25:00.000+01:00",
                        "nodes": [
                            [
                                "origin": "Roma Termini",
                                "destination": "Firenze Santa Maria Novella",
                                "arrivalTime": "2026-11-21T10:25:00.000+01:00",
                                "train": ["name": "FR 9620", "acronym": "FR", "urban": false]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: jsonObj)
        let matches = StationCommuteMatcher.parseDirectLefrecceMatches(
            from: data,
            currentStationName: "Roma Termini",
            targetStationName: "Firenze S.M.N."
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.trainNumber, "9620")
        XCTAssertEqual(matches.first?.estimatedArrivalTime, "10:25")

        // Fermata soppressa deve essere ignorata
        let stopsWithSuppressed = [
            Stop(stationName: "Roma Termini", time: "09:00", actualTime: nil, delay: 0, estimatedTime: nil, plannedPlatform: "1", actualPlatform: nil, isSuppressed: false),
            Stop(stationName: "Firenze S.M.N.", time: "10:25", actualTime: nil, delay: 0, estimatedTime: nil, plannedPlatform: "4", actualPlatform: nil, isSuppressed: true),
            Stop(stationName: "Bologna Centrale", time: "11:05", actualTime: nil, delay: 0, estimatedTime: nil, plannedPlatform: "6", actualPlatform: nil, isSuppressed: false),
        ]
        XCTAssertNil(StationNameMatcher.stopsContainOrderedRoute(stops: stopsWithSuppressed, originStationName: "Roma Termini", targetStations: ["Firenze Santa Maria Novella"]))
        let bolognaHit = StationNameMatcher.stopsContainOrderedRoute(stops: stopsWithSuppressed, originStationName: "Roma Termini", targetStations: ["Bologna C.le"])
        XCTAssertEqual(bolognaHit?.arrivalTime, "11:05")

        // Verifica merge deterministico multi-stazione (sceglie arrivo più presto)
        let earlier = CommuteTrainMatch(trainNumber: "24652", matchedTargetStation: "Milano Porta Garibaldi", estimatedArrivalTime: "18:45", source: .lefrecce)
        let later = CommuteTrainMatch(trainNumber: "24652", matchedTargetStation: "Milano Repubblica", estimatedArrivalTime: "18:48", source: .lefrecce)
        XCTAssertTrue(StationCommuteMatcher.shouldPreferCandidate(earlier, candidateTargetIndex: 1, over: later, existingTargetIndex: 0, referenceMinutes: 18 * 60))
        XCTAssertFalse(StationCommuteMatcher.shouldPreferCandidate(later, candidateTargetIndex: 0, over: earlier, existingTargetIndex: 1, referenceMinutes: 18 * 60))
    }

    @MainActor
    func testStationBoardFilterStorePersistenceTTLAndPerStationSuburban() {
        let suiteName = "InOrarioFilterStoreTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = StationBoardFilterStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        var state = StationBoardFilterState()
        state.commuteTarget = .home
        state.selectedCategories = [.regional]
        state.selectedSuburbanLines = ["S6"]
        state.hideCancelled = true

        store.saveState(state, for: "Milano Porta Garibaldi", now: t0)

        // Riaprendo un'altra stazione entro 10 minuti: commuteTarget, categoria e hideCancelled restano,
        // mentre la linea suburbana S6 resta confinata solo a Milano Porta Garibaldi
        let t10 = t0.addingTimeInterval(10 * 60)
        let loadedRoma = store.loadState(for: "Roma Termini", hasSupport: true, now: t10)
        XCTAssertEqual(loadedRoma.commuteTarget, .home)
        XCTAssertEqual(loadedRoma.selectedCategories, [.regional])
        XCTAssertTrue(loadedRoma.selectedSuburbanLines.isEmpty)
        XCTAssertTrue(loadedRoma.hideCancelled)

        // Tornando a Milano Porta Garibaldi entro TTL, anche S6 è ripristinata (e la finestra scorrevole si rinnova)
        let t11 = t10.addingTimeInterval(60)
        let loadedMilano = store.loadState(for: "Milano P. Garibaldi", hasSupport: true, now: t11)
        XCTAssertEqual(loadedMilano.selectedSuburbanLines, ["S6"])

        // Pausa quando si apre la stazione di casa: apply non filtra il filtro casa/lavoro
        let sampleBoard = [
            Train(category: "REG", number: "2020", destination: "Torino", time: "19:00", delay: "In orario", platform: "1"),
            Train(category: "FR", number: "9600", destination: "Roma", time: "19:10", delay: "In orario", platform: "2"),
        ]
        let pausedResult = loadedRoma.apply(to: sampleBoard, favoriteTrainNumbers: [], commuteMatches: [:], isAlreadyAtTargetStation: true)
        XCTAssertEqual(pausedResult.map(\.number), ["2020"]) // REG applicato, commuteTarget in pausa

        // Scadenza dopo oltre 15 minuti dall'ultimo accesso (t11)
        let expired = store.loadState(for: "Roma Termini", hasSupport: true, now: t11.addingTimeInterval(15 * 60 + 1))
        XCTAssertFalse(expired.isActive)
    }

    @MainActor
    func testCommuteArrivalFormatterAbbreviations() {
        XCTAssertEqual(
            CommuteArrivalFormatter.displayCandidates(stationName: "Milano Porta Garibaldi", arrivalTime: "02:00"),
            ["Arrivo a Milano P. Garibaldi alle 02:00", "Arrivo a Mi. P. Garibaldi alle 02:00"]
        )
        XCTAssertEqual(
            CommuteArrivalFormatter.displayCandidates(stationName: "Milano Centrale", arrivalTime: "02:00"),
            ["Arrivo a Milano Centrale alle 02:00", "Arrivo a Mi. Centrale alle 02:00"]
        )
        XCTAssertEqual(
            CommuteArrivalFormatter.displayCandidates(stationName: "Torino Porta Nuova", arrivalTime: "08:15"),
            ["Arrivo a Torino P. Nuova alle 08:15"]
        )
        XCTAssertEqual(
            CommuteArrivalFormatter.displayCandidates(stationName: "Magenta", arrivalTime: "18:42"),
            ["Arrivo a Magenta alle 18:42"]
        )
        XCTAssertEqual(
            CommuteArrivalFormatter.displayCandidates(stationName: "Milano Greco Pirelli", arrivalTime: "08:15"),
            ["Arrivo a Mi. Greco Pirelli alle 08:15"]
        )
    }

    // MARK: - 15. Granular Commute Time Bands & On-Device Train Discovery Tests

    func testCommuteTimeBandParsingFormattingAndAdjustment() {
        let morning = CommuteTimeBand.parse("09:00 - 09:30")
        XCTAssertEqual(morning.startMinutes, 9 * 60)
        XCTAssertEqual(morning.endMinutes, 9 * 60 + 30)
        XCTAssertEqual(morning.durationMinutes, 30)
        XCTAssertEqual(morning.durationLabel, "30 min")
        XCTAssertEqual(morning.formatted, "09:00 - 09:30")
        XCTAssertEqual(morning.compactFormatted, "09:00-09:30")
        XCTAssertTrue(morning.contains(timeString: "09:00"))
        XCTAssertTrue(morning.contains(timeString: "09:19"))
        XCTAssertTrue(morning.contains(timeString: "09:30"))
        XCTAssertFalse(morning.contains(timeString: "09:31"))

        let evening = CommuteTimeBand.parse("17:00 - 19:00")
        XCTAssertEqual(evening.durationMinutes, 120)
        XCTAssertEqual(evening.durationLabel, "2h")

        // Modifica ora di inizio: preserva la fine se rimane valida (15m..360m), altrimenti mantiene durata
        let shiftedEarlier = morning.updatingStart(to: 8 * 60 + 45)
        XCTAssertEqual(shiftedEarlier.formatted, "08:45 - 09:30")
        let shiftedPastEnd = morning.updatingStart(to: 10 * 60)
        XCTAssertEqual(shiftedPastEnd.formatted, "10:00 - 10:30")

        // Modifica ora di fine: blocca minimo a 15m ed evita wrap involontari indietro
        let clampedMin = morning.updatingEnd(to: 9 * 60 + 5)
        XCTAssertEqual(clampedMin.formatted, "09:00 - 09:15")
        let clampedBefore = morning.updatingEnd(to: 8 * 60 + 30)
        XCTAssertEqual(clampedBefore.formatted, "09:00 - 09:15")

        // Fascia a cavallo della mezzanotte
        let midnight = CommuteTimeBand.parse("23:15 - 00:15")
        XCTAssertEqual(midnight.durationMinutes, 60)
        XCTAssertEqual(midnight.durationLabel, "1h")
        XCTAssertTrue(midnight.contains(timeString: "23:40"))
        XCTAssertTrue(midnight.contains(timeString: "00:10"))
        XCTAssertFalse(midnight.contains(timeString: "00:30"))
    }

    func testDayCommuteScheduleTrainsCodableAndLegacyCompatibility() throws {
        let legacyJSON = #"{"isEnabled":true,"outboundBand":"09:00 - 09:30","returnBand":"17:00 - 19:00"}"#.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(DayCommuteSchedule.self, from: legacyJSON)
        XCTAssertEqual(decodedLegacy.outboundBand, "09:00 - 09:30")
        XCTAssertEqual(decodedLegacy.returnBand, "17:00 - 19:00")
        XCTAssertTrue(decodedLegacy.outboundTrains.isEmpty)
        XCTAssertTrue(decodedLegacy.returnTrains.isEmpty)
        XCTAssertFalse(decodedLegacy.outboundTrainsCustomized)
        XCTAssertFalse(decodedLegacy.returnTrainsCustomized)

        let manualTrain = CommuteHabitTrain(
            trainNumber: "24625",
            category: "S6",
            originStation: "Magenta",
            destinationStation: "Milano Porta Garibaldi",
            departureTime: "08:49",
            arrivalTime: "09:24",
            isManuallyAdded: true
        )
        let custom = DayCommuteSchedule(
            isEnabled: true,
            outboundBand: "09:00 - 09:30",
            returnBand: "17:00 - 19:00",
            outboundTrains: [manualTrain],
            returnTrains: [],
            outboundTrainsCustomized: true,
            returnTrainsCustomized: false
        )
        let encoded = try JSONEncoder().encode(custom)
        let roundTripped = try JSONDecoder().decode(DayCommuteSchedule.self, from: encoded)
        XCTAssertEqual(roundTripped, custom)
        XCTAssertEqual(roundTripped.outboundTrains.first?.isManuallyAdded, true)
    }

    func testCommuteTrainDiscoveryParsingAndDeduplication() throws {
        let jsonString = """
        {
          "solutions": [
            {
              "solution": {
                "origin": "Magenta",
                "destination": "Milano Porta Garibaldi",
                "departureTime": "2026-11-30T09:04:00.000+01:00",
                "arrivalTime": "2026-11-30T09:39:00.000+01:00",
                "nodes": [
                  {
                    "origin": "Magenta",
                    "destination": "Milano Porta Garibaldi",
                    "departureTime": "2026-11-30T09:04:00.000+01:00",
                    "arrivalTime": "2026-11-30T09:39:00.000+01:00",
                    "train": { "name": "S6 24627", "trainCategory": "Suburbano", "acronym": "S6", "urban": false }
                  }
                ]
              }
            },
            {
              "solution": {
                "origin": "Magenta",
                "destination": "Milano Porta Garibaldi",
                "departureTime": "2026-11-30T09:19:00.000+01:00",
                "arrivalTime": "2026-11-30T09:49:00.000+01:00",
                "nodes": [
                  {
                    "origin": "Magenta",
                    "destination": "Milano Porta Garibaldi",
                    "departureTime": "2026-11-30T09:19:00.000+01:00",
                    "arrivalTime": "2026-11-30T09:49:00.000+01:00",
                    "train": { "name": "RV 2017", "trainCategory": "Regionale Veloce", "acronym": "RV", "urban": false }
                  }
                ]
              }
            },
            {
              "solution": {
                "origin": "Magenta",
                "destination": "Milano Porta Garibaldi",
                "departureTime": "2026-11-30T09:34:00.000+01:00",
                "arrivalTime": "2026-11-30T10:09:00.000+01:00",
                "nodes": [
                  {
                    "origin": "Magenta",
                    "destination": "Milano Porta Garibaldi",
                    "departureTime": "2026-11-30T09:34:00.000+01:00",
                    "arrivalTime": "2026-11-30T10:09:00.000+01:00",
                    "train": { "name": "S6 24629", "trainCategory": "Suburbano", "acronym": "S6", "urban": false }
                  }
                ]
              }
            },
            {
              "solution": {
                "origin": "Magenta",
                "destination": "Milano Porta Garibaldi",
                "departureTime": "2026-11-30T09:10:00.000+01:00",
                "arrivalTime": "2026-11-30T09:50:00.000+01:00",
                "nodes": [
                  { "origin": "Magenta", "destination": "Rho", "departureTime": "2026-11-30T09:10:00.000+01:00", "arrivalTime": "2026-11-30T09:25:00.000+01:00", "train": { "name": "S6 24628", "urban": false } },
                  { "origin": "Rho", "destination": "Milano Porta Garibaldi", "departureTime": "2026-11-30T09:30:00.000+01:00", "arrivalTime": "2026-11-30T09:50:00.000+01:00", "train": { "name": "Metro", "urban": true } }
                ]
              }
            }
          ]
        }
        """
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let band = CommuteTimeBand.parse("09:00 - 09:30")
        let parsed = CommuteTrainDiscoveryService.parseLefrecceBandTrains(
            from: data,
            originStation: "Magenta",
            destinationStation: "Milano Porta Garibaldi",
            band: band
        )
        XCTAssertEqual(parsed.totalSolutions, 4)
        XCTAssertEqual(parsed.trains.map(\.trainNumber), ["24627", "2017"])
        XCTAssertEqual(parsed.trains.map(\.category), ["S6", "RV"])

        // Deduplica multi-destinazione/origine & preservazione treni manuali fuori fascia
        let duplicateSameTrain = CommuteHabitTrain(
            trainNumber: "24627",
            category: "S6",
            originStation: "Magenta",
            destinationStation: "Milano Repubblica",
            departureTime: "09:04",
            arrivalTime: "09:42",
            isManuallyAdded: false
        )
        let deduped = CommuteTrainDiscoveryService.deduplicateAndSort(
            parsed.trains + [duplicateSameTrain],
            origins: ["Magenta"],
            band: band
        )
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped.first?.arrivalTime, "09:39")

        let manualEarly = CommuteHabitTrain(
            trainNumber: "24625",
            category: "S6",
            originStation: "Magenta",
            destinationStation: "Milano Porta Garibaldi",
            departureTime: "08:49",
            arrivalTime: "09:24",
            isManuallyAdded: true
        )
        let merged = CommuteTrainDiscoveryService.mergeDiscoveredWithExisting(
            discovered: deduped,
            existing: [manualEarly],
            band: band,
            origins: ["Magenta"]
        )
        XCTAssertEqual(merged.map(\.trainNumber), ["24625", "24627", "2017"])

        // nextDate ritorna il giorno ISO della settimana richiesto strettamente nel futuro
        let ref = Date(timeIntervalSince1970: 1_763_980_800) // Lun 24 Nov 2025
        let nextWed = CommuteTrainDiscoveryService.nextDate(forISOWeekday: 3, hour: 9, minute: 0, referenceDate: ref)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        let isoWd = ((cal.component(.weekday, from: nextWed) + 5) % 7) + 1
        XCTAssertEqual(isoWd, 3)
        XCTAssertGreaterThan(nextWed, ref)
    }

    @MainActor
    func testBuildCommuteSyncPayloadIncludesPerDayTrains() throws {
        let mgr = SupporterCommuteManager.shared
        let defaults = UserDefaults.standard
        let hadSupId = defaults.object(forKey: "supporter_eternal_id")
        let hadSupport = defaults.object(forKey: "tip.colazionee")
        let prevOrigins = mgr.origins
        let prevDests = mgr.destinations
        let prevCustom = mgr.customizePerDay
        let prevWeekdays = mgr.activeWeekdays
        let prevSchedules = mgr.daySchedules
        let prevOutBand = mgr.defaultOutboundBand
        let prevRetBand = mgr.defaultReturnBand

        defer {
            if let s = hadSupId { defaults.set(s, forKey: "supporter_eternal_id") } else { defaults.removeObject(forKey: "supporter_eternal_id") }
            if let h = hadSupport { defaults.set(h, forKey: "tip.colazionee") } else { defaults.removeObject(forKey: "tip.colazionee") }
            mgr.origins = prevOrigins
            mgr.destinations = prevDests
            mgr.customizePerDay = prevCustom
            mgr.activeWeekdays = prevWeekdays
            mgr.daySchedules = prevSchedules
            mgr.defaultOutboundBand = prevOutBand
            mgr.defaultReturnBand = prevRetBand
        }

        defaults.set("sup_test_trains_payload", forKey: "supporter_eternal_id")
        defaults.set(true, forKey: "tip.colazionee")
        mgr.origins = ["Magenta"]
        mgr.destinations = ["Milano Porta Garibaldi"]
        mgr.activeWeekdays = [1, 2]
        mgr.defaultOutboundBand = "09:00 - 09:30"
        mgr.defaultReturnBand = "17:00 - 19:00"

        let monTrain = CommuteHabitTrain(
            trainNumber: "24627",
            category: "S6",
            originStation: "Magenta",
            destinationStation: "Milano Porta Garibaldi",
            departureTime: "09:04",
            arrivalTime: "09:39",
            isManuallyAdded: false
        )
        let tueExtra = CommuteHabitTrain(
            trainNumber: "2017",
            category: "RV",
            originStation: "Magenta",
            destinationStation: "Milano Centrale",
            departureTime: "09:19",
            arrivalTime: "09:49",
            isManuallyAdded: true
        )
        mgr.daySchedules = [
            1: DayCommuteSchedule(isEnabled: true, outboundBand: "09:00 - 09:30", returnBand: "17:00 - 19:00", outboundTrains: [monTrain]),
            2: DayCommuteSchedule(isEnabled: true, outboundBand: "08:30 - 09:30", returnBand: "17:30 - 18:30", outboundTrains: [monTrain, tueExtra]),
        ]

        // 1. Modalità globale con treni diversi fra Lunedì e Martedì -> divide in due gruppi
        mgr.customizePerDay = false
        let globalPayload = try XCTUnwrap(mgr.buildCommuteSyncPayload())
        let globalSchedules = try XCTUnwrap(globalPayload["schedules"] as? [[String: Any]])
        let globalOutbounds = globalSchedules.filter { ($0["type"] as? String) == "outbound" }
        XCTAssertEqual(globalOutbounds.count, 2)
        XCTAssertEqual(globalOutbounds[0]["weekdays"] as? [Int], [1])
        XCTAssertEqual(globalOutbounds[0]["trains"] as? [String], ["24627"])
        XCTAssertEqual(globalOutbounds[1]["weekdays"] as? [Int], [2])
        XCTAssertEqual(globalOutbounds[1]["trains"] as? [String], ["24627", "2017"])

        // 2. Modalità per singolo giorno -> include fasce granulari e train_details per ciascun giorno
        mgr.customizePerDay = true
        let perDayPayload = try XCTUnwrap(mgr.buildCommuteSyncPayload())
        let perDaySchedules = try XCTUnwrap(perDayPayload["schedules"] as? [[String: Any]])
        let monOutbound = try XCTUnwrap(perDaySchedules.first(where: { ($0["type"] as? String) == "outbound" && ($0["weekdays"] as? [Int]) == [1] }))
        XCTAssertEqual(monOutbound["time"] as? String, "09:00 - 09:30")
        XCTAssertEqual(monOutbound["trains"] as? [String], ["24627"])
        let monDetails = try XCTUnwrap(monOutbound["train_details"] as? [[String: Any]])
        XCTAssertEqual(monDetails.first?["departure_time"] as? String, "09:04")
    }

    @MainActor
    func testHomeBannerPlanBSuppressedOnSummaryOkUnlessFollowed() throws {
        let mgr = SupporterCommuteManager.shared
        let defaults = UserDefaults.standard
        let hadSupport = defaults.object(forKey: "tip.colazionee")
        let prevActive = mgr.activePlanB
        let prevPinned = mgr.pinnedPlanB
        let prevChosen = mgr.chosenAlternativeId

        defer {
            if let h = hadSupport { defaults.set(h, forKey: "tip.colazionee") } else { defaults.removeObject(forKey: "tip.colazionee") }
            mgr.activePlanB = prevActive
            mgr.pinnedPlanB = prevPinned
            mgr.chosenAlternativeId = prevChosen
        }

        defaults.set(true, forKey: "tip.colazionee")
        mgr.pinnedPlanB = nil
        mgr.chosenAlternativeId = nil

        let alt = PlanBAlternativeItem(
            train_number: "24638",
            category: "S6",
            destination: "Magenta",
            station: "Milano Dateo",
            departure_time: "12:10",
            arrival_time: "12:54",
            duration: "44min",
            delay: 0,
            platform: "2",
            transfer_info: "Treno diretto (44min)",
            legs: nil
        )

        let summaryOkPlan = PlanBReportDTO(
            title: "🟢 Circolazione regolare (12:00 - 13:00)",
            body: "Circolazione regolare. Prossimo treno: S6 24638 delle 12:10 da Milano Dateo (in orario).",
            incident_type: "summary_ok",
            incident_detail: nil,
            cancelled_train: nil,
            target_time: "12:00 - 13:00",
            origins: ["Milano Dateo"],
            destinations: ["Magenta"],
            alternatives: [alt],
            timestamp: "2026-11-24T11:45:00"
        )

        // 1. Con summary_ok e nessun treno seguito, la striscia sulla Home NON deve apparire
        mgr.activePlanB = summaryOkPlan
        XCTAssertNil(mgr.homeBannerPlanB)

        // 2. Se l'utente tocca esplicitamente "Segui" su un treno del riepilogo, la striscia appare
        mgr.chosenAlternativeId = alt.id
        XCTAssertNotNil(mgr.homeBannerPlanB)

        // 3. Con un disservizio reale (summary_critical o delay), la striscia appare anche senza aver ancora scelto un treno
        mgr.chosenAlternativeId = nil
        let criticalPlan = PlanBReportDTO(
            title: "🔴 Disservizi sulla tratta (12:00 - 13:00)",
            body: "Attenzione: treno 24638 in ritardo di +17'.",
            incident_type: "summary_critical",
            incident_detail: nil,
            cancelled_train: nil,
            target_time: "12:00 - 13:00",
            origins: ["Milano Dateo"],
            destinations: ["Magenta"],
            alternatives: [alt],
            timestamp: "2026-11-24T11:45:00"
        )
        mgr.activePlanB = criticalPlan
        XCTAssertNotNil(mgr.homeBannerPlanB)
        XCTAssertEqual(mgr.homeBannerPlanB?.incident_type, "summary_critical")
    }

    // MARK: - Metro Station Matching Exhaustive Audit

    func testMetroLinesNeverAppearOnWrongStationsAcrossEntireRFICatalog() throws {
        struct RawRFIStation: Decodable {
            let id: String?
            let name: String
            let vtID: String?
            let lat: Double?
            let lon: Double?
        }

        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("In Orario")
            .appendingPathComponent("rfi_stations.json")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode([RawRFIStation].self, from: data)
        XCTAssertGreaterThan(catalog.count, 3000, "Expected full Italian RFI catalog")

        let expectedByName: [String: (city: String, expectedPdfIDs: Set<String>)] = [
            // Milano (18 stazioni RFI/FN)
            "RHO FIERA": ("milano", ["RHO FIERAMILANO"]),
            "MILANO PORTA GARIBALDI": ("milano", ["GARIBALDI FS"]),
            "MILANO PORTA GARIBALDI SOTTERRANEA": ("milano", ["GARIBALDI FS"]),
            "MILANO CENTRALE": ("milano", ["CENTRALE FS"]),
            "MILANO REPUBBLICA": ("milano", ["REPUBBLICA"]),
            "MILANO PORTA VENEZIA": ("milano", ["P.TA VENEZIA"]),
            "MILANO DATEO": ("milano", ["DATEO"]),
            "MILANO FORLANINI": ("milano", ["STAZIONE FORLANINI"]),
            "SESTO S.GIOVANNI": ("milano", ["SESTO 1 MAGGIO FS"]),
            "MILANO CADORNA": ("milano", ["CADORNA FN M1", "CADORNA FN M2"]),
            "MILANO LAMBRATE": ("milano", ["LAMBRATE FS"]),
            "MILANO PORTA GENOVA": ("milano", ["PORTA GENOVA FS"]),
            "MILANO ROMOLO": ("milano", ["ROMOLO"]),
            "MILANO AFFORI": ("milano", ["AFFORI FN"]),
            "MILANO SCALO ROMANA": ("milano", ["LODI T.I.B.B."]),
            "MILANO ROGOREDO": ("milano", ["ROGOREDO FS"]),
            "MILANO S.CRISTOFORO": ("milano", ["SAN CRISTOFORO"]),
            "MILANO DOMODOSSOLA": ("milano", ["DOMODOSSOLA FN"]),
            // Napoli (3)
            "NAPOLI CENTRALE": ("napoli", ["PIAZZA GARIBALDI"]),
            "NAPOLI PIAZZA GARIBALDI": ("napoli", ["PIAZZA GARIBALDI"]),
            "NAPOLI PIAZZA CAVOUR": ("napoli", ["MUSEO"]),
            // Torino (3)
            "TORINO PORTA NUOVA": ("torino", ["METRO PORTA NUOVA"]),
            "TORINO PORTA SUSA": ("torino", ["METRO PORTA SUSA"]),
            "TORINO LINGOTTO": ("torino", ["METRO LINGOTTO"]),
            // Roma (4)
            "ROMA TERMINI": ("roma", ["Termini"]),
            "ROMA TIBURTINA": ("roma", ["Tiburtina F.s."]),
            "ROMA OSTIENSE": ("roma", ["Piramide"]),
            "VALLE AURELIA": ("roma", ["Valle Aurelia"])
        ]

        var matchedWithIDs = Set<String>()
        var matchedByNameOnly = Set<String>()

        for entry in catalog {
            let stationWithIDs = Station(name: entry.name, rfiID: entry.id, vtID: entry.vtID, lat: entry.lat, lon: entry.lon)
            let stationNameOnly = Station(name: entry.name, rfiID: nil, vtID: nil, lat: nil, lon: nil)

            let linesWithIDs = stationWithIDs.metroLines
            let linesNameOnly = stationNameOnly.metroLines

            if let expected = expectedByName[entry.name] {
                XCTAssertFalse(linesWithIDs.isEmpty, "Expected metro lines (by ID) for \(entry.name)")
                XCTAssertFalse(linesNameOnly.isEmpty, "Expected metro lines (by name) for \(entry.name)")
                XCTAssertEqual(Set(linesWithIDs.map(\.city)), [expected.city], "Wrong city (by ID) for \(entry.name)")
                XCTAssertEqual(Set(linesNameOnly.map(\.city)), [expected.city], "Wrong city (by name) for \(entry.name)")
                XCTAssertEqual(Set(linesWithIDs.compactMap(\.pdfID)), expected.expectedPdfIDs, "Wrong metro stop (by ID) for \(entry.name)")
                XCTAssertEqual(Set(linesNameOnly.compactMap(\.pdfID)), expected.expectedPdfIDs, "Wrong metro stop (by name) for \(entry.name)")
                matchedWithIDs.insert(entry.name)
                matchedByNameOnly.insert(entry.name)
            } else {
                XCTAssertTrue(
                    linesWithIDs.isEmpty,
                    "FALSE POSITIVE (by ID): \(entry.name) (rfi=\(entry.id ?? "nil"), vt=\(entry.vtID ?? "nil")) unexpectedly got metro lines: \(linesWithIDs.map { "\($0.city):\($0.name)" })"
                )
                XCTAssertTrue(
                    linesNameOnly.isEmpty,
                    "FALSE POSITIVE (by name only): \(entry.name) unexpectedly got metro lines: \(linesNameOnly.map { "\($0.city):\($0.name)" })"
                )
            }
        }

        XCTAssertEqual(matchedWithIDs, Set(expectedByName.keys))
        XCTAssertEqual(matchedByNameOnly, Set(expectedByName.keys))
    }

    func testMetroLinesForSuburbanPassanteAndProblematicAliases() {
        // Stazioni che prima attivavano erroneamente la metro di Milano
        let mustHaveNoMetro = [
            "Venezia Mestre",
            "Venezia S.Lucia",
            "Venezia Santa Lucia",
            "Venezia Carpenedo",
            "Venezia Porto Marghera",
            "Bologna Centrale",
            "Trieste Centrale",
            "Treviso Centrale",
            "Bari Centrale",
            "Palermo Centrale",
            "Pisa Centrale",
            "Pavia Porta Garibaldi",
            "Casalecchio Garibaldi",
            "Domodossola",
            "S.Cristoforo al Lago-Ischia",
            "Viterbo Porta Romana",
            "Potenza Macchia Romana",
            "Sesto Fiorentino",
            "Sesto Calende",
            "Sesto Campano",
            "Rho",
            "Genova Piazza Principe",
            "Verona Porta Nuova",
            "Termini Imerese",
            "Roma Aurelia",
            "Vittoria"
        ]
        for name in mustHaveNoMetro {
            let s = Station(name: name, rfiID: nil, vtID: nil, lat: nil, lon: nil)
            XCTAssertTrue(s.metroLines.isEmpty, "\(name) must NOT show any metro lines")
        }

        // Alias legittimi Passante / Milano / Napoli
        XCTAssertEqual(Set(Station(name: "Porta Venezia", rfiID: "1723", vtID: "S01649").metroLines.compactMap(\.pdfID)), ["P.TA VENEZIA"])
        XCTAssertEqual(Set(Station(name: "P. Garibaldi Passante", rfiID: "1714", vtID: "S01647").metroLines.compactMap(\.pdfID)), ["GARIBALDI FS"])
        XCTAssertEqual(Set(Station(name: "Repubblica", rfiID: "1719", vtID: "S01648").metroLines.compactMap(\.pdfID)), ["REPUBBLICA"])
        XCTAssertEqual(Set(Station(name: "Dateo", rfiID: "3468", vtID: "S01650").metroLines.compactMap(\.pdfID)), ["DATEO"])
        XCTAssertEqual(Set(Station(name: "Forlanini", rfiID: "3169", vtID: "S01492").metroLines.compactMap(\.pdfID)), ["STAZIONE FORLANINI"])
        XCTAssertEqual(Set(Station(name: "Napoli Centrale", rfiID: "1888", vtID: "S09218").metroLines.map(\.city)), ["napoli"])
        XCTAssertEqual(Set(Station(name: "Napoli Piazza Garibaldi", rfiID: "1880", vtID: "S09109").metroLines.map(\.city)), ["napoli"])

        // localResolveUrbanLeg non deve scambiare stazioni non milanesi per Milano Centrale
        XCTAssertNil(TrainManager.localResolveUrbanLeg(orig: "Bologna Centrale", dest: "Milano Porta Garibaldi", time: "10:00"))
        XCTAssertNil(TrainManager.localResolveUrbanLeg(orig: "Napoli Centrale", dest: "Milano Lambrate", time: "10:00"))
        XCTAssertNotNil(TrainManager.localResolveUrbanLeg(orig: "Milano Centrale", dest: "Milano Porta Garibaldi", time: "10:00"))

        // formatDestination non deve mai rinominare stazioni di altre città in stazioni di Milano
        XCTAssertEqual(SharedFormatters.formatDestination("Venezia Mestre"), "Venezia Mestre")
        XCTAssertEqual(SharedFormatters.formatDestination("Venezia"), "Venezia")
        XCTAssertEqual(SharedFormatters.formatDestination("Vittoria"), "Vittoria")
        XCTAssertEqual(SharedFormatters.formatDestination("Trieste Centrale"), "Trieste Centrale")
        XCTAssertEqual(SharedFormatters.formatDestination("Bologna Centrale"), "Bologna Centrale")
        XCTAssertEqual(SharedFormatters.formatDestination("Napoli Piazza Garibaldi"), "Napoli Piazza Garibaldi")
        XCTAssertEqual(SharedFormatters.formatDestination("Milano Porta Venezia"), "Milano P. Venezia")
        XCTAssertEqual(SharedFormatters.formatDestination("Porta Venezia"), "Milano P. Venezia")
        XCTAssertEqual(SharedFormatters.formatDestination("Milano Porta Vittoria"), "Milano P. Vittoria")
    }

    func testStationMatchesDoesNotCollideAcrossCities() {
        let milanoCentrale = Station(name: "MILANO CENTRALE", rfiID: "1728", vtID: "S01700")
        let bolognaCentrale = Station(name: "BOLOGNA CENTRALE", rfiID: "683", vtID: "S05043")
        let triesteCentrale = Station(name: "TRIESTE CENTRALE", rfiID: "2925", vtID: "S03317")
        let napoliCentrale = Station(name: "NAPOLI CENTRALE", rfiID: "1888", vtID: "S09218")
        let milanoCentraleNoID = Station(name: "Milano Centrale", rfiID: nil, vtID: nil)
        let bolognaCentraleNoID = Station(name: "Bologna Centrale", rfiID: nil, vtID: nil)

        XCTAssertFalse(milanoCentrale.matches(bolognaCentrale))
        XCTAssertFalse(milanoCentrale.matches(triesteCentrale))
        XCTAssertFalse(milanoCentrale.matches(napoliCentrale))
        XCTAssertFalse(milanoCentrale.matches(bolognaCentraleNoID))
        XCTAssertFalse(milanoCentraleNoID.matches(bolognaCentrale))
        XCTAssertTrue(milanoCentrale.matches(milanoCentraleNoID))

        let milanoDomodossola = Station(name: "MILANO DOMODOSSOLA", rfiID: nil, vtID: "S01067")
        let domodossola = Station(name: "DOMODOSSOLA", rfiID: "1253", vtID: "S01003")
        let domodossolaNoID = Station(name: "Domodossola", rfiID: nil, vtID: nil)
        XCTAssertFalse(milanoDomodossola.matches(domodossola))
        XCTAssertFalse(milanoDomodossola.matches(domodossolaNoID))

        let milanoCristoforo = Station(name: "MILANO S.CRISTOFORO", rfiID: "1721", vtID: "S01630")
        let trentinoCristoforo = Station(name: "S.CRISTOFORO AL LAGO-ISCHIA", rfiID: "2480", vtID: "S02306")
        XCTAssertFalse(milanoCristoforo.matches(trentinoCristoforo))

        let milanoRomana = Station(name: "Milano Porta Romana", rfiID: nil, vtID: nil)
        let viterboRomana = Station(name: "VITERBO PORTA ROMANA", rfiID: "3116", vtID: "S08306")
        XCTAssertFalse(milanoRomana.matches(viterboRomana))

        let rho = Station(name: "RHO", rfiID: "2345", vtID: "S01037")
        let rhoFiera = Station(name: "RHO FIERA", rfiID: "3098", vtID: "S01039")
        XCTAssertFalse(rho.matches(rhoFiera))

        let garibaldiSup = Station(name: "MILANO PORTA GARIBALDI", rfiID: "1715", vtID: "S01645")
        let garibaldiPass = Station(name: "MILANO PORTA GARIBALDI SOTTERRANEA", rfiID: "1714", vtID: "S01647")
        let napoliGaribaldi = Station(name: "NAPOLI PIAZZA GARIBALDI", rfiID: "1880", vtID: "S09109")
        let paviaGaribaldi = Station(name: "PAVIA PORTA GARIBALDI", rfiID: "2301", vtID: "S01861")
        XCTAssertFalse(garibaldiSup.matches(garibaldiPass))
        XCTAssertFalse(garibaldiSup.matches(napoliGaribaldi))
        XCTAssertFalse(garibaldiSup.matches(paviaGaribaldi))

        let milanoVenezia = Station(name: "MILANO PORTA VENEZIA", rfiID: "1723", vtID: "S01649")
        let passanteVenezia = Station(name: "Porta Venezia", rfiID: nil, vtID: nil)
        let veneziaMestre = Station(name: "VENEZIA MESTRE", rfiID: "3002", vtID: "S02589")
        XCTAssertTrue(milanoVenezia.matches(passanteVenezia))
        XCTAssertFalse(milanoVenezia.matches(veneziaMestre))

        let milanoCertosa = Station(name: "MILANO CERTOSA", rfiID: "1708", vtID: "S01640")
        let passanteCertosa = Station(name: "Certosa", rfiID: nil, vtID: nil)
        let certosaPavia = Station(name: "CERTOSA DI PAVIA", rfiID: "1069", vtID: "S01803")
        XCTAssertTrue(milanoCertosa.matches(passanteCertosa))
        XCTAssertFalse(milanoCertosa.matches(certosaPavia))

        let milanoRepubblica = Station(name: "MILANO REPUBBLICA", rfiID: "1719", vtID: "S01648")
        let passanteRepubblica = Station(name: "Repubblica", rfiID: nil, vtID: nil)
        XCTAssertTrue(milanoRepubblica.matches(passanteRepubblica))
    }

    @MainActor
    func testResolveStationIdentityAcrossEntireRFICatalog() async throws {
        struct RawRFIStation: Decodable {
            let id: String?
            let name: String
            let vtID: String?
        }

        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("In Orario")
            .appendingPathComponent("rfi_stations.json")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode([RawRFIStation].self, from: data)
        XCTAssertGreaterThan(catalog.count, 3000)

        let manager = TrainManager()
        await manager.loadRFIStationsAsync()

        // Nessun hijack alfabetico o troncamento parola
        for entry in catalog {
            let resolved = manager.resolveStation(name: entry.name)
            XCTAssertFalse(resolved.name.isEmpty)
            // Se i codici esistono, o corrispondono esattamente all'entry o a una stazione omonima legittima
            if let expectedRfi = entry.id, !expectedRfi.isEmpty {
                XCTAssertEqual(resolved.rfiID, expectedRfi, "rfiID mismatch resolving \(entry.name): got \(resolved.name) (\(resolved.rfiID ?? "nil"))")
            }
        }

        // Casi specifici critici dell'audit
        XCTAssertEqual(manager.resolveStation(name: "RIVAROLO").name, "RIVAROLO")
        XCTAssertEqual(manager.resolveStation(name: "S.BIAGIO").name, "S.BIAGIO")
        XCTAssertEqual(manager.resolveStation(name: "S.LORENZO").name, "S.LORENZO")
        XCTAssertEqual(manager.resolveStation(name: "GENOVA PIAZZA PRINCIPE SOTTERRANEA").rfiID, "255")
        XCTAssertEqual(manager.resolveStation(name: "GENOVA PIAZZA PRINCIPE").rfiID, "257")
        XCTAssertEqual(manager.resolveStation(name: "SAN PAOLO").rfiID, "3155")
        XCTAssertEqual(manager.resolveStation(name: "S.PAOLO").vtID, "S12423")
        XCTAssertEqual(manager.resolveStation(name: "REGGIO MEDIOPADANA", fallbackVtID: "S05195").vtID, "S05195")
        XCTAssertEqual(manager.resolveStation(name: "MILANO SCALO ROMANA").name, "MILANO SCALO ROMANA")
        XCTAssertEqual(manager.resolveStation(name: "MILANO DOMODOSSOLA").vtID, "S01067")
        XCTAssertEqual(manager.resolveStation(name: "DOMODOSSOLA").vtID, "S01003")
        XCTAssertEqual(manager.resolveStation(name: "S.CRISTOFORO AL LAGO-ISCHIA").rfiID, "2480")
        XCTAssertEqual(manager.resolveStation(name: "VITERBO PORTA ROMANA").rfiID, "3116")
        XCTAssertEqual(manager.resolveStation(name: "Sesto San Giovanni").rfiID, "2716")
        XCTAssertEqual(manager.resolveStation(name: "Torino P. Susa").rfiID, "3163")
        XCTAssertEqual(manager.resolveStation(name: "Firenze S. M. Novella").rfiID, "1325")
        XCTAssertEqual(manager.resolveStation(name: "Venezia S. Lucia").rfiID, "3009")
    }

    @MainActor
    func testSettingsUsageTrackerAndHabitCommuteSlot() {
        // 1. Cancella abitudini apprese svuota davvero tutte le fasce anche con preferiti presenti
        let tracker = UsageTracker()
        tracker.clearHistory()
        let favStations = [
            Station(name: "Magenta", rfiID: "1564", vtID: "S01040", lat: nil, lon: nil),
            Station(name: "Milano Centrale", rfiID: "1728", vtID: "S01700", lat: nil, lon: nil)
        ]
        let favTrains = [
            SavedTrain(number: "24627", description: "Novara - Pioltello", departureTime: "08:15")
        ]
        let emptySlots = tracker.learnedHabitsByTimeSlot(favoriteTrains: favTrains, favoriteStations: favStations)
        XCTAssertTrue(emptySlots.allSatisfy { $0.isEmpty }, "After clearHistory(), all learned habit slots must be empty")

        // 2. Ordine deterministico delle stazioni con stesso punteggio
        let now = Date()
        tracker.stationVisits = [
            StationVisit(stationName: "Novara", vtID: nil, rfiID: nil, date: now, weekday: 2, hour: 8, gpsConfirmed: false),
            StationVisit(stationName: "Arona", vtID: nil, rfiID: nil, date: now, weekday: 2, hour: 8, gpsConfirmed: false),
            StationVisit(stationName: "Magenta", vtID: nil, rfiID: nil, date: now, weekday: 2, hour: 8, gpsConfirmed: false)
        ]
        let run1 = tracker.learnedHabitsByTimeSlot(favoriteTrains: [], favoriteStations: [])[0].stations.map { $0.name }
        let run2 = tracker.learnedHabitsByTimeSlot(favoriteTrains: [], favoriteStations: [])[0].stations.map { $0.name }
        XCTAssertEqual(run1, ["Arona", "Magenta", "Novara"])
        XCTAssertEqual(run1, run2)
        tracker.clearHistory()

        // 3. Finestra oraria Viaggio abituale (lead 45m, trail 30m)
        XCTAssertTrue(SupporterCommuteManager.isMinute(6 * 60 + 20, withinBand: "07:00 - 08:00"))
        XCTAssertTrue(SupporterCommuteManager.isMinute(7 * 60 + 30, withinBand: "07:00 - 08:00"))
        XCTAssertTrue(SupporterCommuteManager.isMinute(8 * 60 + 25, withinBand: "07:00 - 08:00"))
        XCTAssertFalse(SupporterCommuteManager.isMinute(6 * 60 + 00, withinBand: "07:00 - 08:00"))
        XCTAssertFalse(SupporterCommuteManager.isMinute(9 * 60 + 00, withinBand: "07:00 - 08:00"))
        XCTAssertTrue(SupporterCommuteManager.isMinute(0 * 60 + 15, withinBand: "23:00 - 00:00"))

        // 4. Visibilità sezioni Dashboard
        let tm = TrainManager()
        tm.setSectionVisible(.favoriteRoutes, false)
        XCTAssertFalse(tm.isSectionVisible(.favoriteRoutes))
        tm.setSectionVisible(.favoriteRoutes, true)
        XCTAssertTrue(tm.isSectionVisible(.favoriteRoutes))
    }

    func testTipManagerResolveEntitlementPriorityAndRevocation() {
        let yearly = TipManager.resolveEntitlement(from: [
            (productID: TipManager.yearlySubscriptionID, originalID: 101, isRevoked: false)
        ])
        XCTAssertTrue(yearly.isSupporter)
        XCTAssertEqual(yearly.tier, .yearly)
        XCTAssertEqual(yearly.originalID, 101)

        let lifetime = TipManager.resolveEntitlement(from: [
            (productID: TipManager.lifetimeProductID, originalID: 202, isRevoked: false)
        ])
        XCTAssertTrue(lifetime.isSupporter)
        XCTAssertEqual(lifetime.tier, .lifetime)
        XCTAssertEqual(lifetime.originalID, 202)

        let legacy = TipManager.resolveEntitlement(from: [
            (productID: TipManager.legacyProductID, originalID: 303, isRevoked: false)
        ])
        XCTAssertTrue(legacy.isSupporter)
        XCTAssertEqual(legacy.tier, .legacy)
        XCTAssertEqual(legacy.originalID, 303)

        // Lifetime has priority over yearly regardless of StoreKit enumeration order
        let combined = TipManager.resolveEntitlement(from: [
            (productID: TipManager.yearlySubscriptionID, originalID: 101, isRevoked: false),
            (productID: TipManager.lifetimeProductID, originalID: 202, isRevoked: false)
        ])
        XCTAssertTrue(combined.isSupporter)
        XCTAssertEqual(combined.tier, .lifetime)
        XCTAssertEqual(combined.originalID, 202)

        // Revoked transactions are ignored
        let revokedOnly = TipManager.resolveEntitlement(from: [
            (productID: TipManager.lifetimeProductID, originalID: 202, isRevoked: true)
        ])
        XCTAssertFalse(revokedOnly.isSupporter)
        XCTAssertNil(revokedOnly.tier)
        XCTAssertNil(revokedOnly.originalID)

        let empty = TipManager.resolveEntitlement(from: [])
        XCTAssertFalse(empty.isSupporter)
        XCTAssertNil(empty.tier)
        XCTAssertNil(empty.originalID)
    }

    @MainActor
    func testAIFeatureManagerUpgradeAutoUnlocksCloudAndPreservesManualChoice() {
        let defaults = UserDefaults.standard
        let keys = [
            "aiModeChoice",
            "aiModeUserExplicitlyChosen",
            "aiModeLastObservedSupport",
            "premium_preferLocalAI",
            "selectedModelID",
            "tip.colazionee"
        ]
        var savedValues: [String: Any] = [:]
        for k in keys {
            if let v = defaults.object(forKey: k) {
                savedValues[k] = v
            }
        }
        defer {
            for k in keys {
                if let v = savedValues[k] {
                    defaults.set(v, forKey: k)
                } else {
                    defaults.removeObject(forKey: k)
                }
            }
        }

        let ai = AIFeatureManager.shared
        // 1. Utente Free che aveva scelto manualmente "Senza IA"
        defaults.set(false, forKey: "aiModeLastObservedSupport")
        ai.hasUserChosenAIMode = true
        ai.aiModeChoice = .none
        ai.preferLocalAI = false
        ai.reconcileDefaultAIMode(hasSupport: false)
        XCTAssertEqual(ai.aiModeChoice, .none)

        // 2. Passaggio a Pro -> sblocca automaticamente Cloud IA anche se hasUserChosenAIMode era true
        ai.reconcileDefaultAIMode(hasSupport: true)
        XCTAssertEqual(ai.aiModeChoice, .cloud)
        XCTAssertFalse(ai.preferLocalAI)
        XCTAssertTrue(defaults.bool(forKey: "aiModeLastObservedSupport"))

        // 3. Da Pro già attivo, una scelta manuale successiva (es. .none) viene rispettata
        ai.aiModeChoice = .none
        ai.hasUserChosenAIMode = true
        ai.reconcileDefaultAIMode(hasSupport: true)
        XCTAssertEqual(ai.aiModeChoice, .none)

        // 4. Downgrade da .cloud -> lascia .cloud
        ai.aiModeChoice = .cloud
        ai.reconcileDefaultAIMode(hasSupport: false)
        XCTAssertNotEqual(ai.aiModeChoice, .cloud)
        XCTAssertFalse(defaults.bool(forKey: "aiModeLastObservedSupport"))
    }

    func testNewsAlwaysPrefersGeminiBackendAcrossAllRegionsAndModes() {
        let regions = ["Tutte", "Lombardia", "Puglia", "Friuli Venezia Giulia", "Sicilia", "Valle d'Aosta"]
        let modes: [AIFeatureManager.AIMode] = [.none, .local, .cloud]
        for reg in regions {
            for mode in modes {
                for hasSupport in [false, true] {
                    for preferLocal in [false, true] {
                        XCTAssertTrue(
                            TrainManager.shouldPreferBackendNews(
                                hasSupport: hasSupport,
                                strikeRegion: reg,
                                aiModeChoice: mode,
                                preferLocalAI: preferLocal
                            ),
                            "Expected Gemini backend news for region=\(reg), mode=\(mode), support=\(hasSupport)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - FollowedTrip & Transfer Margin Tests

    func testTransferMarginCalculation() {
        XCTAssertEqual(
            FollowedTripCardView.transferMargin(arr: "10:00", arrDelay: 0, dep: "10:10", depDelay: 0, walk: 0),
            10
        )
        XCTAssertEqual(
            FollowedTripCardView.transferMargin(arr: "10:00", arrDelay: 8, dep: "10:10", depDelay: 0, walk: 0),
            2
        )
        XCTAssertEqual(
            FollowedTripCardView.transferMargin(arr: "10:00", arrDelay: 8, dep: "10:10", depDelay: 0, walk: 3),
            -1
        )
        XCTAssertEqual(
            FollowedTripCardView.transferMargin(arr: "23:55", arrDelay: 0, dep: "00:05", depDelay: 0, walk: 0),
            10
        )
        XCTAssertNil(
            FollowedTripCardView.transferMargin(arr: "--:--", arrDelay: 0, dep: "10:10", depDelay: 0, walk: 0)
        )
    }

    func testFollowedTripIsSingleTrain() {
        let alt = PlanBAlternativeItem(
            train_number: "2461",
            category: "REG",
            destination: "Milano Centrale",
            station: "Rho",
            departure_time: "08:00",
            arrival_time: "08:40",
            duration: "40m",
            delay: 0,
            platform: "1",
            transfer_info: "",
            legs: nil
        )
        let trainLeg1 = PlanBLegItem(
            train_number: "2461",
            category: "REG",
            origin: "Rho",
            destination: "Milano Porta Garibaldi",
            departure_time: "08:00",
            arrival_time: "08:20",
            delay: 0,
            platform: "1",
            is_urban: false,
            is_station_walk: false,
            travel_minutes: 20,
            urban_headsign: nil
        )
        let metroLeg = PlanBLegItem(
            train_number: "M2",
            category: "Metro M2",
            origin: "Garibaldi FS",
            destination: "Centrale FS",
            departure_time: "08:25",
            arrival_time: "08:32",
            delay: 0,
            platform: "",
            is_urban: true,
            is_station_walk: false,
            travel_minutes: 7,
            urban_headsign: "Cologno Nord"
        )
        let walkLeg = PlanBLegItem(
            train_number: "piedi",
            category: "Interscambio a piedi",
            origin: "Milano Porta Garibaldi",
            destination: "Milano Porta Garibaldi Passante",
            departure_time: "08:20",
            arrival_time: "08:25",
            delay: 0,
            platform: "",
            is_urban: false,
            is_station_walk: true,
            travel_minutes: 5,
            urban_headsign: nil
        )
        let trainLeg2 = PlanBLegItem(
            train_number: "2500",
            category: "REG",
            origin: "Milano Porta Garibaldi",
            destination: "Monza",
            departure_time: "08:30",
            arrival_time: "08:45",
            delay: 0,
            platform: "3",
            is_urban: false,
            is_station_walk: false,
            travel_minutes: 15,
            urban_headsign: nil
        )

        let trainPlusMetro = FollowedTrip(
            alternative: alt,
            legs: [trainLeg1, metroLeg],
            dayKey: "2026-11-25",
            createdAt: Date()
        )
        XCTAssertTrue(trainPlusMetro.isSingleTrain)
        XCTAssertEqual(trainPlusMetro.railLegs.count, 1)

        let trainPlusWalkPlusTrain = FollowedTrip(
            alternative: alt,
            legs: [trainLeg1, walkLeg, trainLeg2],
            dayKey: "2026-11-25",
            createdAt: Date()
        )
        XCTAssertFalse(trainPlusWalkPlusTrain.isSingleTrain)
        XCTAssertEqual(trainPlusWalkPlusTrain.railLegs.count, 2)
    }

    func testPlanBStationMatch() {
        XCTAssertTrue(planBStationMatch("Milano P. Garibaldi", "Milano Porta Garibaldi"))
        XCTAssertTrue(planBStationMatch("Milano Centrale", "MILANO CENTRALE"))
        XCTAssertFalse(planBStationMatch("Milano Centrale", "Torino Porta Nuova"))
    }

    @MainActor
    func testFollowedTripFromTravelSolutionAndPlanBRestore() {
        let commute = SupporterCommuteManager.shared
        let defaults = UserDefaults.standard
        let oldSupport = defaults.object(forKey: "tip.colazionee")
        let oldFollowed = commute.followedTrip
        let oldActivePlanB = commute.activePlanB
        let oldPinnedPlanB = commute.pinnedPlanB
        let oldChosenId = commute.chosenAlternativeId

        defer {
            if let oldSupport {
                defaults.set(oldSupport, forKey: "tip.colazionee")
            } else {
                defaults.removeObject(forKey: "tip.colazionee")
            }
            commute.followedTrip = oldFollowed
            commute.activePlanB = oldActivePlanB
            if let oldPinned = oldPinnedPlanB {
                commute.pinPlanB(oldPinned)
            } else {
                commute.unpinPlanB()
            }
            commute.chosenAlternativeId = oldChosenId
        }

        let seg1 = TravelSegment(
            origin: "Magenta",
            destination: "Milano Porta Garibaldi",
            departureTime: "10:15",
            arrivalTime: "10:45",
            trainNumber: "2461",
            trainCategory: "Suburbano S6",
            travelMinutes: 30
        )
        let seg2 = TravelSegment(
            origin: "Garibaldi FS",
            destination: "Cadorna FN",
            departureTime: "10:50",
            arrivalTime: "11:00",
            trainNumber: "M2",
            trainCategory: "Trasporto Urbano",
            travelMinutes: 10,
            urbanHeadsign: "Abbiategrasso"
        )
        let seg3 = TravelSegment(
            origin: "Milano Cadorna",
            destination: "Castano Primo",
            departureTime: "11:10",
            arrivalTime: "11:55",
            trainNumber: "321",
            trainCategory: "REG",
            travelMinutes: 45
        )
        let solution = TravelSolution(
            trainNumber: "2461",
            category: "Suburbano S6",
            departureTime: "10:15",
            arrivalTime: "11:55",
            origin: "Magenta",
            destination: "Castano Primo",
            duration: "1h 40m",
            segments: [seg1, seg2, seg3]
        )

        let followed = FollowedTrip.from(solution: solution)
        XCTAssertFalse(followed.isSingleTrain)
        XCTAssertEqual(followed.railLegs.count, 2)
        XCTAssertEqual(followed.toTravelSolution().segments.count, 3)

        defaults.set(true, forKey: "tip.colazionee")
        let delayPlan = PlanBReportDTO(
            title: "Ritardo sulla linea",
            body: "Alternative disponibili",
            incident_type: "delay",
            incident_detail: nil,
            cancelled_train: nil,
            target_time: "10:15",
            origins: ["Magenta"],
            destinations: ["Milano"],
            alternatives: [],
            timestamp: "2026-11-25T10:00:00Z"
        )
        commute.activePlanB = delayPlan
        commute.pinPlanB(delayPlan)
        commute.followSolution(solution)
        commute.clearPlanBAfterFollow()

        XCTAssertNotNil(commute.activePlanB)
        XCTAssertNil(commute.homeBannerPlanB)

        commute.followedTrip = nil
        XCTAssertEqual(commute.homeBannerPlanB?.title, "Ritardo sulla linea")
    }

    // MARK: - 5-Tab Redesign, Contextual Search & Personal Lines Tests

    func testMainTabBarOrderAndLaunchFallback() {
        XCTAssertEqual(MainTab.barOrder, [.trains, .stations, .home, .trips, .lines])
        XCTAssertEqual(MainTab.barOrder[2], .home)
        XCTAssertEqual(MainTab.resolvedLaunchTab(rawValue: nil), .home)
        XCTAssertEqual(MainTab.resolvedLaunchTab(rawValue: "unknown_tab"), .home)
        XCTAssertEqual(MainTab.resolvedLaunchTab(rawValue: MainTab.trains.rawValue), .trains)
        XCTAssertEqual(MainTab.resolvedLaunchTab(rawValue: MainTab.lines.rawValue), .lines)
        // Changing launch screen preference never changes bar order
        XCTAssertEqual(MainTab.barOrder.first, .trains)
        XCTAssertEqual(MainTab.barOrder.last, .lines)
    }

    @MainActor
    func testContextualSearchScopeAndHistoryMapping() {
        XCTAssertEqual(MainTab.trains.defaultSearchScope, .trainsAndStations)
        XCTAssertEqual(MainTab.stations.defaultSearchScope, .trainsAndStations)
        XCTAssertEqual(MainTab.home.defaultSearchScope, .trainsAndStations)
        XCTAssertEqual(MainTab.trips.defaultSearchScope, .solutions)
        XCTAssertEqual(MainTab.lines.defaultSearchScope, .trainsAndStations)

        XCTAssertEqual(MainTab.trains.defaultHistoryTabIndex, 2)
        XCTAssertEqual(MainTab.stations.defaultHistoryTabIndex, 1)
        XCTAssertEqual(MainTab.trips.defaultHistoryTabIndex, 0)
        XCTAssertEqual(MainTab.home.defaultHistoryTabIndex, 0)
        XCTAssertEqual(MainTab.lines.defaultHistoryTabIndex, 0)

        let coordinator = MainNavigationCoordinator(launchTabRawValue: MainTab.trains.rawValue)
        XCTAssertEqual(coordinator.selectedTab, .trains)
        XCTAssertTrue(coordinator.mountedTabs.contains(.trains))
        XCTAssertTrue(coordinator.mountedTabs.contains(.home))

        // Selecting an already active tab produces a popToRoot token without unmounting
        XCTAssertNil(coordinator.popToRootTokens[.trains])
        coordinator.selectTab(.trains)
        XCTAssertNotNil(coordinator.popToRootTokens[.trains])

        coordinator.selectTab(.trips)
        XCTAssertEqual(coordinator.selectedTab, .trips)
        XCTAssertTrue(coordinator.mountedTabs.contains(.trips))

        coordinator.openContextualSearch()
        XCTAssertEqual(coordinator.activeSearchRequest?.scope, .solutions)
    }

    func testAppSectionDisplayTitlesAndTolerantDecoding() throws {
        XCTAssertEqual(AppSection.myStations.displayTitle, "Stazioni")
        XCTAssertEqual(AppSection.favoriteTrains.displayTitle, "Treni")
        XCTAssertEqual(AppSection.favoriteRoutes.displayTitle, "Viaggi e Tratte")
        XCTAssertEqual(AppSection.passante.displayTitle, "Linee")

        // Ensures legacy or removed raw values (like "News, Scioperi e Lavori") are ignored cleanly without dropping user order
        let legacyWithRemovedJSON = #"["Stazione Vicina","News, Scioperi e Lavori","I miei Treni","Le Mie Stazioni","Le Mie Tratte Abituali","Linee Suburbane"]"#
        let data = try XCTUnwrap(legacyWithRemovedJSON.data(using: .utf8))
        let rawStrings = try JSONDecoder().decode([String].self, from: data)
        var loaded = rawStrings.compactMap { AppSection(rawValue: $0) }
        for section in AppSection.allCases where !loaded.contains(section) {
            loaded.append(section)
        }
        XCTAssertEqual(loaded, [.nearby, .favoriteTrains, .myStations, .favoriteRoutes, .passante])
    }

    @MainActor
    func testCompactStationNameFormatting() {
        XCTAssertEqual("Milano Porta Garibaldi".compactStationName, "Milano P. Garibaldi")
        XCTAssertEqual("Torino Porta Nuova".compactStationName, "Torino P. Nuova")
        XCTAssertEqual("Milano Porta Venezia".compactStationName, "Milano P. Venezia")
    }

    @MainActor
    func testStationBoardSnapshotEvaluation() {
        let station = Station(name: "Milano Centrale", rfiID: "1728", vtID: "S01700")

        let emptySnapshot = TrainManager.evaluateStationBoardSnapshot(
            station: station,
            result: StationBoardResult(trains: [], alerts: nil)
        )
        XCTAssertEqual(emptySnapshot.circulationState, .noData)
        XCTAssertEqual(emptySnapshot.healthMessage, "Dati non disponibili")

        let minorDelays = [
            Train(category: "FR", number: "9604", destination: "Torino P.N.", time: "08:00", delay: "In orario", platform: "4"),
            Train(category: "RV", number: "2044", destination: "Verona P.N.", time: "08:15", delay: "+2'", platform: "8"),
            Train(category: "REG", number: "24501", destination: "Bergamo", time: "08:20", delay: "+8'", platform: "1")
        ]
        let regularSnapshot = TrainManager.evaluateStationBoardSnapshot(
            station: station,
            result: StationBoardResult(trains: minorDelays, alerts: nil)
        )
        XCTAssertEqual(regularSnapshot.circulationState, .regular)
        XCTAssertEqual(regularSnapshot.healthMessage, "Circolazione regolare")
        XCTAssertEqual(regularSnapshot.cancelledCount, 0)

        let moderateIssues = [
            Train(category: "REG", number: "24503", destination: "Bergamo", time: "08:30", delay: "+12'", platform: "2"),
            Train(category: "REG", number: "24505", destination: "Pavia", time: "08:40", delay: "+3'", platform: "3")
        ]
        let warningSnapshot = TrainManager.evaluateStationBoardSnapshot(
            station: station,
            result: StationBoardResult(trains: moderateIssues, alerts: nil)
        )
        XCTAssertEqual(warningSnapshot.circulationState, .warning)
        XCTAssertEqual(warningSnapshot.healthMessage, "Rallentamenti dir. Bergamo")

        let disrupted = [
            Train(category: "REG", number: "1001", destination: "Lodi", time: "08:50", delay: "Soppresso", platform: "-"),
            Train(category: "REG", number: "1003", destination: "Novara", time: "09:00", delay: "Cancellato", platform: "-")
        ]
        let disruptedSnapshot = TrainManager.evaluateStationBoardSnapshot(
            station: station,
            result: StationBoardResult(trains: disrupted, alerts: nil)
        )
        XCTAssertEqual(disruptedSnapshot.circulationState, .disrupted)
        XCTAssertTrue(disruptedSnapshot.healthMessage.hasPrefix("Soppressioni dir."))
        XCTAssertEqual(disruptedSnapshot.cancelledCount, 2)
    }

    @MainActor
    func testPersonalLinesHonestHealthAndSuggestions() async {
        let trainManager = TrainManager()
        let passanteManager = PassanteManager()
        let usageTracker = UsageTracker()
        let commuteManager = SupporterCommuteManager.shared
        let linesManager = PersonalLinesManager()

        let prevFavs = trainManager.favoriteTrains
        let prevRoutes = trainManager.favoriteRoutes
        defer {
            trainManager.favoriteTrains = prevFavs
            trainManager.favoriteRoutes = prevRoutes
            trainManager.saveFavorites()
        }

        trainManager.favoriteTrains = [
            SavedTrain(number: "24501", description: "Varese - Treviglio", category: "S5")
        ]
        trainManager.favoriteRoutes = [
            FavoriteRoute(originName: "Milano Centrale", originID: "S01700", destinationName: "Bergamo", destinationID: "S01407")
        ]

        // Remove if already persisted in test environment before evaluating suggestion output
        linesManager.removeLine(id: "S5", passanteManager: nil)
        linesManager.removeLine(id: "MI-BG", passanteManager: nil)

        linesManager.rebuildSuggestions(
            trainManager: trainManager,
            passanteManager: passanteManager,
            usageTracker: usageTracker,
            commuteManager: commuteManager
        )

        XCTAssertTrue(linesManager.suggestedLines.contains(where: { $0.id == "S5" }))
        XCTAssertTrue(linesManager.suggestedLines.contains(where: { $0.id == "MI-BG" }))

        // Honest health status: zero observed trains/alerts must never fake .regular
        let emptyHealth: LineHealthStatus = .noDataYet(reason: "Nessun treno attivo rilevato ora")
        XCTAssertEqual(emptyHealth.semanticKind, .neutral)

        if let s5 = RailwayLineCatalog.curatedCatalog.first(where: { $0.id == "S5" }) {
            linesManager.addLine(s5, passanteManager: nil)
            linesManager.rebuildSuggestions(
                trainManager: trainManager,
                passanteManager: passanteManager,
                usageTracker: usageTracker,
                commuteManager: commuteManager
            )
            XCTAssertFalse(linesManager.suggestedLines.contains(where: { $0.id == "S5" }))
            linesManager.removeLine(id: "S5", passanteManager: nil)
        }
    }

    @MainActor
    func testStationUniqueMetroLineBadgesDeduplicatesDirections() {
        let garibaldi = Station(name: "Milano Porta Garibaldi", rfiID: "1714", vtID: "S01647")
        XCTAssertEqual(garibaldi.uniqueMetroLineBadges.map(\.code), ["M2", "M5"])

        let centrale = Station(name: "Milano Centrale", rfiID: "1728", vtID: "S01700")
        XCTAssertEqual(centrale.uniqueMetroLineBadges.map(\.code), ["M2", "M3"])

        let rho = Station(name: "Rho Fiera", rfiID: "3098", vtID: "S01039")
        XCTAssertEqual(rho.uniqueMetroLineBadges.map(\.code), ["M1"])
    }

    func testTrainsFilterModeOptions() {
        XCTAssertEqual(TrainsFilterMode.allCases, [.all, .inTransit, .delayedOrAlert, .regular, .withAlerts])
        XCTAssertEqual(TrainsFilterMode.withAlerts.rawValue, "Con avvisi attivi")
        XCTAssertEqual(TrainsFilterMode.inTransit.rawValue, "In viaggio")
    }

    func testNewsItemStrikeAndLineRelevanceHelpers() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "Europe/Rome")
        let todayISO = df.string(from: Date())

        let todayStrike = NewsItem(
            title: "Sciopero nazionale trasporto ferroviario",
            content: "Disagi possibili tutto il giorno",
            isUrgent: true,
            category: "sciopero",
            date: todayISO
        )
        XCTAssertTrue(todayStrike.isStrikeCategory)
        XCTAssertTrue(todayStrike.isStrikeToday)
        XCTAssertEqual(todayStrike.daysUntilStrike, 0)

        let works = NewsItem(
            title: "Lavori programmati tra Milano Centrale e Bergamo",
            content: "Modifiche alla circolazione dei treni S5 e RE",
            isUrgent: false,
            category: "lavori",
            workLocation: "Linea Milano - Bergamo"
        )
        XCTAssertTrue(works.isWorksCategory)
        XCTAssertFalse(works.isStrikeCategory)
        XCTAssertTrue(works.isRelevantToUser(stationNames: ["Bergamo"], lineCodes: []))
        XCTAssertTrue(works.isRelevantToUser(stationNames: [], lineCodes: ["S5"]))
        XCTAssertFalse(works.isRelevantToUser(stationNames: ["Napoli Centrale"], lineCodes: ["M4"]))
    }

    @MainActor
    func testFavoriteRouteIsReversedPersistenceAndBackwardCompatibility() throws {
        // 1. Legacy JSON without `isReversed` decodes safely with effectiveIsReversed == false
        let legacyJSON = """
        {
            "originName": "Magenta",
            "originID": "S01042",
            "destinationName": "Milano Dateo",
            "destinationID": "S01645"
        }
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(FavoriteRoute.self, from: legacyJSON)
        XCTAssertNil(decodedLegacy.isReversed)
        XCTAssertFalse(decodedLegacy.effectiveIsReversed)
        XCTAssertEqual(decodedLegacy.effectiveOriginName, "Magenta")
        XCTAssertEqual(decodedLegacy.effectiveDestinationName, "Milano Dateo")
        XCTAssertTrue(decodedLegacy.matchesUndirected(originID: "S01645", destID: "S01042"))

        // 2. Reversed computed endpoints & TrainManager persistence
        let tm = TrainManager()
        let prevRoutes = tm.favoriteRoutes
        defer {
            tm.favoriteRoutes = prevRoutes
            tm.saveFavorites()
        }

        tm.favoriteRoutes = [decodedLegacy]
        XCTAssertTrue(tm.isFavoriteRoute(originID: "S01645", destID: "S01042"))

        tm.setFavoriteRouteReversed(routeID: decodedLegacy.id, isReversed: true)
        XCTAssertEqual(tm.favoriteRoutes.first?.effectiveIsReversed, true)
        XCTAssertEqual(tm.favoriteRoutes.first?.effectiveOriginName, "Milano Dateo")
        XCTAssertEqual(tm.favoriteRoutes.first?.effectiveOriginID, "S01645")
        XCTAssertEqual(tm.favoriteRoutes.first?.effectiveDestinationName, "Magenta")
        XCTAssertEqual(tm.favoriteRoutes.first?.effectiveDestinationID, "S01042")

        // Verify persistence roundtrip via UserDefaults
        let tmReloaded = TrainManager()
        let reloaded = tmReloaded.favoriteRoutes.first { $0.id == decodedLegacy.id }
        XCTAssertEqual(reloaded?.effectiveIsReversed, true)
        XCTAssertEqual(reloaded?.effectiveOriginName, "Milano Dateo")
        XCTAssertEqual(reloaded?.effectiveDestinationName, "Magenta")
    }

    @MainActor
    func testUsageTrackerLearnedHabitRoutesConsolidationAndExclusion() {
        let tracker = UsageTracker()
        let prevUsages = tracker.routeUsages
        let prevIgnored = tracker.ignoredRouteKeys
        defer {
            tracker.routeUsages = prevUsages
            tracker.ignoredRouteKeys = prevIgnored
        }

        tracker.ignoredRouteKeys = []
        let cal = Calendar.current
        let now = Date()
        let day1 = cal.date(byAdding: .day, value: -1, to: now)!
        let day2 = cal.date(byAdding: .day, value: -3, to: now)!
        let day3 = cal.date(byAdding: .day, value: -6, to: now)!

        tracker.routeUsages = [
            // Undirected consolidation across A->B and B->A on 3 distinct days
            RouteUsage(originID: "S01042", originName: "Magenta", destID: "S01700", destName: "Milano Centrale", date: day1, weekday: 2, hour: 8),
            RouteUsage(originID: "S01700", originName: "Milano Centrale", destID: "S01042", destName: "Magenta", date: day2, weekday: 4, hour: 18),
            RouteUsage(originID: "S01042", originName: "Magenta", destID: "S01700", destName: "Milano Centrale", date: day3, weekday: 6, hour: 8),
            // Insufficient distinct days (only 2 days) -> excluded
            RouteUsage(originID: "S01645", originName: "Milano Dateo", destID: "S01860", destName: "Pavia", date: day1, weekday: 2, hour: 9),
            RouteUsage(originID: "S01645", originName: "Milano Dateo", destID: "S01860", destName: "Pavia", date: day2, weekday: 4, hour: 9)
        ]

        let habits = tracker.learnedHabitRoutes(excluding: [], limit: 3, at: now)
        XCTAssertEqual(habits.count, 1)
        XCTAssertEqual(habits.first?.distinctDays, 3)

        // When saved in reversed orientation, must be excluded from suggestions
        let reversedFav = FavoriteRoute(originName: "Milano Centrale", originID: "S01700", destinationName: "Magenta", destinationID: "S01042")
        let excludedHabits = tracker.learnedHabitRoutes(excluding: [reversedFav], limit: 3, at: now)
        XCTAssertTrue(excludedHabits.isEmpty)
    }

    @MainActor
    func testItalianRailwayLineCatalogLoadsAndSeparatesAVFromRegional() async throws {
        let catalog = RailwayLineCatalog.curatedCatalog
        XCTAssertEqual(catalog.count, 191)
        XCTAssertEqual(Set(catalog.map(\.id)).count, 191)

        // All 6 kinds represented
        let kinds = Set(catalog.map(\.kind))
        XCTAssertTrue(kinds.contains(.suburban))
        XCTAssertTrue(kinds.contains(.regional))
        XCTAssertTrue(kinds.contains(.highSpeed))
        XCTAssertTrue(kinds.contains(.intercity))
        XCTAssertTrue(kinds.contains(.international))
        XCTAssertTrue(kinds.contains(.airport))

        let miTo = try XCTUnwrap(catalog.first(where: { $0.id == "MI-TO" }))
        XCTAssertEqual(miTo.kind, .regional)
        XCTAssertEqual(miTo.stations.first, "Torino Porta Nuova")
        XCTAssertEqual(miTo.stations.last, "Milano Centrale")
        XCTAssertFalse(miTo.categoryPrefixes.contains("FR"))
        XCTAssertFalse(miTo.categoryPrefixes.contains("ITA"))

        let avMiTo = try XCTUnwrap(catalog.first(where: { $0.id == "AV-TO-MI" }))
        XCTAssertEqual(avMiTo.kind, .highSpeed)
        XCTAssertEqual(avMiTo.stations.first, "Torino Porta Nuova")
        XCTAssertEqual(avMiTo.stations.last, "Milano Centrale")
        XCTAssertTrue(avMiTo.categoryPrefixes.contains("FR"))
        XCTAssertTrue(avMiTo.categoryPrefixes.contains("ITA"))
        XCTAssertTrue(avMiTo.categoryPrefixes.contains("NTV"))
        XCTAssertFalse(avMiTo.stations.contains("Magenta"))

        // Check AV Bologna deduplication
        for avID in ["AV-MI-BO", "AV-BO-FI", "AV-VE-BO"] {
            let avLine = try XCTUnwrap(catalog.first(where: { $0.id == avID }))
            XCTAssertTrue(avLine.stations.contains("Bologna C.le/AV"))
            XCTAssertFalse(avLine.stations.contains("Bologna Centrale"))
        }

        // Check TILO, Intercity, International, South & Islands lines
        for requiredID in ["S10", "S19", "S40", "S50", "MI-CO", "IC-TIR", "IC-ADR", "EC-GOTT", "EC-BREN", "AV-FR", "PA-SFM", "CA-IGL", "GE-URB", "5T-EXP", "BA-MET", "RC-MET"] {
            XCTAssertNotNil(catalog.first(where: { $0.id == requiredID }), "Missing line \(requiredID)")
        }

        XCTAssertEqual(catalog.first(where: { $0.id == "S19" })?.code, "S19")
        XCTAssertEqual(catalog.first(where: { $0.id == "S6" })?.stations.first, "Novara")
        XCTAssertEqual(catalog.first(where: { $0.id == "S6" })?.stations.last, "Treviglio")
        XCTAssertEqual(catalog.first(where: { $0.id == "S6" })?.branches?.first?.effectiveIsDashed, true)
        XCTAssertEqual(catalog.first(where: { $0.id == "S13" })?.branches?.first?.effectivePosition, .before)
        XCTAssertEqual(catalog.first(where: { $0.id == "MXP" })?.branches?.first?.stations, ["Milano Cadorna"])
        XCTAssertEqual(catalog.first(where: { $0.id == "FL4" })?.branches?.count, 2)
        XCTAssertEqual(catalog.first(where: { $0.id == "SFM3" })?.branches?.first?.stations, ["Susa"])
        XCTAssertEqual(catalog.first(where: { $0.id == "SFM3" })?.branches?.first?.effectivePosition, .before)
        XCTAssertEqual(catalog.first(where: { $0.id == "MI-BG" })?.code, "RE2")
        XCTAssertEqual(catalog.first(where: { $0.id == "MI-BS-VR" })?.code, "RE6")
        XCTAssertEqual(catalog.first(where: { $0.id == "MI-LAV" })?.code, "RE1")

        // Verify all 14 branched lines have valid junctions & branch stations
        let branchedLines = catalog.filter { !($0.branches ?? []).isEmpty }
        XCTAssertEqual(branchedLines.count, 14)
        for line in branchedLines {
            for br in line.branches ?? [] {
                XCTAssertTrue(line.stations.contains(br.junctionStation), "Missing junction \(br.junctionStation) in \(line.id)")
                for bs in br.stations {
                    XCTAssertTrue(line.stations.contains(bs), "Missing branch station \(bs) in \(line.id)")
                }
            }
        }

        // Ensure Milano S1 and Bologna S1 (BO-SFM1) resolve distinctly by stations
        let bolognaMatch = RailwayLineCatalog.findBestCatalogLine(
            matchingStationA: "Porretta Terme",
            stationB: "Bologna Centrale",
            category: "S1"
        )
        XCTAssertEqual(bolognaMatch?.id, "BO-SFM1")

        // Verify JSON station resolution, bilingual names & newly added Italian aliases
        let tm = TrainManager()
        await tm.loadRFIStationsAsync()
        let linesManager = PersonalLinesManager()
        let verifyAliases = [
            "Bolzano/Bozen", "Ora/Auer", "Torino Aeroporto", "Rivarolo Canavese",
            "Bologna C.le/AV", "Porretta Terme", "Firenze Campo di Marte",
            "Punta Raisi", "Reggio di Calabria Aeroporto", "Settimo Torinese",
            "San Candido/Innichen", "Palermo Politeama", "Bojano",
            "Santa Margherita Ligure-Portofino", "Zola Predosa"
        ]
        let stationsWithoutRFICoords: Set<String> = [
            "Torino Aeroporto",
            "Palermo Politeama",
            "Zola Predosa"
        ]
        for name in verifyAliases {
            let st = tm.resolveStation(name: name)
            XCTAssertNotNil(st.vtID, "Missing vtID for \(name)")
            if !stationsWithoutRFICoords.contains(name) {
                XCTAssertNotNil(st.lat, "Missing coordinates for \(name)")
            }
        }
        let s6 = try XCTUnwrap(catalog.first(where: { $0.id == "S6" }))
        let s6Stations = linesManager.resolvedStations(for: s6, trainManager: tm)
        XCTAssertTrue(s6Stations.contains(where: { $0.name.localizedCaseInsensitiveContains("Treviglio") }))
        let s13 = try XCTUnwrap(catalog.first(where: { $0.id == "S13" }))
        let s13Stations = linesManager.resolvedStations(for: s13, trainManager: tm)
        XCTAssertTrue(s13Stations.contains(where: { $0.name.localizedCaseInsensitiveContains("Garbagnate") }))

        // Legacy PersonalLineKind value backward compatibility & new kinds
        let legacyJSON = "\"Regionale / Diretta\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(PersonalLineKind.self, from: legacyJSON), .regional)
        let icJSON = "\"Intercity\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(PersonalLineKind.self, from: icJSON), .intercity)
        let intlJSON = "\"Internazionale\"".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(PersonalLineKind.self, from: intlJSON), .international)
    }

    @MainActor
    func testPersonalLineMatchesTrainSeparatesHighSpeedAndRegional() throws {
        let catalog = RailwayLineCatalog.curatedCatalog
        let miTo = try XCTUnwrap(catalog.first(where: { $0.id == "MI-TO" }))
        let avMiTo = try XCTUnwrap(catalog.first(where: { $0.id == "AV-TO-MI" }))
        let icTir = try XCTUnwrap(catalog.first(where: { $0.id == "IC-TIR" }))
        let ecGott = try XCTUnwrap(catalog.first(where: { $0.id == "EC-GOTT" }))

        let rvTrain = Train(category: "RV", number: "2020", destination: "TORINO PORTA NUOVA", time: "10:15", delay: "In orario", platform: "5")
        let frTrain = Train(category: "FR", number: "9616", destination: "TORINO PORTA NUOVA", time: "10:25", delay: "+5'", platform: "7")
        let ntvTrain = Train(category: "NTV", number: "9970", destination: "TORINO PORTA NUOVA", time: "10:35", delay: "In orario", platform: "8")
        let s6Train = Train(category: "S6", number: "24626", destination: "NOVARA", time: "10:10", delay: "In orario", platform: "2")
        let icTrain = Train(category: "IC", number: "657", destination: "ROMA TERMINI", time: "11:10", delay: "In orario", platform: "6")
        let icnTrain = Train(category: "ICN", number: "1963", destination: "PALERMO CENTRALE", time: "20:10", delay: "In orario", platform: "9")
        let ecTrain = Train(category: "EC", number: "314", destination: "LUGANO", time: "12:10", delay: "In orario", platform: "10")
        let regComoTrain = Train(category: "R", number: "25020", destination: "CHIASSO", time: "12:15", delay: "In orario", platform: "11")

        XCTAssertTrue(PersonalLinesManager.matchesLineTrain(rvTrain, boardStation: "Milano Centrale", line: miTo))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(frTrain, boardStation: "Milano Centrale", line: miTo))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(ntvTrain, boardStation: "Milano Centrale", line: miTo))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(s6Train, boardStation: "Magenta", line: miTo))

        XCTAssertTrue(PersonalLinesManager.matchesLineTrain(frTrain, boardStation: "Milano Centrale", line: avMiTo))
        XCTAssertTrue(PersonalLinesManager.matchesLineTrain(ntvTrain, boardStation: "Milano Centrale", line: avMiTo))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(rvTrain, boardStation: "Milano Centrale", line: avMiTo))

        XCTAssertTrue(PersonalLinesManager.matchesLineTrain(icTrain, boardStation: "Milano Centrale", line: icTir))
        XCTAssertTrue(PersonalLinesManager.matchesLineTrain(icnTrain, boardStation: "Milano Centrale", line: icTir))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(frTrain, boardStation: "Milano Centrale", line: icTir))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(rvTrain, boardStation: "Milano Centrale", line: icTir))

        XCTAssertTrue(PersonalLinesManager.matchesLineTrain(ecTrain, boardStation: "Milano Centrale", line: ecGott))
        XCTAssertFalse(PersonalLinesManager.matchesLineTrain(regComoTrain, boardStation: "Milano Centrale", line: ecGott))
    }

    func testStationInterchangeCatalogHardcodedLookupsAndExclusion() {
        let centrale = StationInterchangeCatalog.interchanges(for: "Milano Centrale")
        XCTAssertTrue(centrale.contains(where: { $0.code == "M2" }))
        XCTAssertTrue(centrale.contains(where: { $0.code == "M3" }))
        XCTAssertTrue(centrale.contains(where: { $0.code == "AV" }))

        let cadorna = StationInterchangeCatalog.interchanges(for: "Milano Cadorna", excludingLineCode: "MXP")
        XCTAssertTrue(cadorna.contains(where: { $0.code == "M1" }))
        XCTAssertTrue(cadorna.contains(where: { $0.code == "S3" }))
        XCTAssertFalse(cadorna.contains(where: { $0.code == "MXP" }))

        let dateo = StationInterchangeCatalog.interchanges(for: "Dateo", excludingLineCode: "S6")
        XCTAssertTrue(dateo.contains(where: { $0.code == "M4" }))
        XCTAssertFalse(dateo.contains(where: { $0.code == "S6" }))

        let roma = StationInterchangeCatalog.interchanges(for: "Roma Termini", excludingLineCode: "AV RM-NA")
        XCTAssertTrue(roma.contains(where: { $0.code == "MA" }))
        XCTAssertTrue(roma.contains(where: { $0.code == "MB" }))
        XCTAssertFalse(roma.contains(where: { $0.code == "AV" }))

        let torinoSusa = StationInterchangeCatalog.interchanges(for: "Torino Porta Susa")
        XCTAssertTrue(torinoSusa.contains(where: { $0.code == "M1" }))
        XCTAssertTrue(torinoSusa.contains(where: { $0.code == "AV" }))
    }

    func testMainTabDefaultHistoryTabIndicesMatchHistoryView() {
        XCTAssertEqual(MainTab.trips.defaultHistoryTabIndex, 0)
        XCTAssertEqual(MainTab.stations.defaultHistoryTabIndex, 1)
        XCTAssertEqual(MainTab.trains.defaultHistoryTabIndex, 2)
        XCTAssertEqual(MainTab.home.defaultHistoryTabIndex, 0)
    }

    func testRFIDelayFormattingAndItalian24HourLocale() {
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("Cancellato"), "Cancellato")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("Soppresso"), "Soppresso")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("14"), "+14'")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("+14'"), "+14'")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("0"), "In orario")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay(""), "In orario")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("In orario"), "In orario")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("-2"), "-2'")
        XCTAssertEqual(StationRepository.formatScrapedRFIDelay("Deviato"), "Deviato")
        XCTAssertEqual(SharedFormatters.italian24HourLocale.hourCycle, .zeroToTwentyThree)
        XCTAssertEqual(SharedFormatters.format24HourTimeString("11:50 AM"), "11:50")
        XCTAssertEqual(SharedFormatters.format24HourTimeString("3:15 PM"), "15:15")
        XCTAssertEqual(SharedFormatters.format24HourTimeString("07:30"), "07:30")
    }

    func testTrainNotificationStandByPauseAndMasterToggles() throws {
        var t1 = SavedTrain(number: "24530", description: "Treviglio - Varese")
        t1.notifyDelay = true
        t1.notifyScheduledTime = true
        t1.scheduledNotificationTime = "7:30 AM"
        XCTAssertTrue(t1.hasAnyConfiguredNotification)
        XCTAssertTrue(t1.hasActiveNotifications)

        // Stand-by pause preserves local configuration but excludes train from server sync payload
        t1.notificationsPaused = true
        XCTAssertTrue(t1.hasAnyConfiguredNotification)
        XCTAssertFalse(t1.hasActiveNotifications)

        var t2 = SavedTrain(number: "24627", description: "Novara - Pioltello")
        t2.notifyScheduledTime = true
        t2.scheduledNotificationTime = "08:15"

        let activePayload = TrainManager.buildNotificationSyncTrainsPayload(
            favoriteTrains: [t1, t2],
            hasSupport: true,
            masterEnabled: true,
            trainsEnabled: true
        )
        XCTAssertEqual(activePayload.count, 1)
        XCTAssertEqual(activePayload.first?["train_number"] as? String, "24627")

        // Unpausing restores server payload with normalized 24h time
        t1.notificationsPaused = false
        let restoredPayload = TrainManager.buildNotificationSyncTrainsPayload(
            favoriteTrains: [t1, t2],
            hasSupport: true,
            masterEnabled: true,
            trainsEnabled: true
        )
        XCTAssertEqual(restoredPayload.count, 2)
        XCTAssertEqual(restoredPayload.first?["scheduled_notification_time"] as? String, "07:30")

        // Master OFF or Trains OFF empties server train payload while preserving local state
        XCTAssertTrue(TrainManager.buildNotificationSyncTrainsPayload(favoriteTrains: [t1, t2], hasSupport: true, masterEnabled: false, trainsEnabled: true).isEmpty)
        XCTAssertTrue(TrainManager.buildNotificationSyncTrainsPayload(favoriteTrains: [t1, t2], hasSupport: true, masterEnabled: true, trainsEnabled: false).isEmpty)

        // Backward-compatible decoding without notificationsPaused key
        let legacyData = #"{"number":"1234","description":"A - B","notifyDelay":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedTrain.self, from: legacyData)
        XCTAssertFalse(decoded.isNotificationsPaused)
        XCTAssertTrue(decoded.hasActiveNotifications)
    }

    func testTelemetryAckValidationAndDeltaSubtractionPreservesInFlightEvents() {
        let validAck = #"{"status":"ok","saved":true,"user_id":"dev-1","batch_id":"batch-abc"}"#.data(using: .utf8)!
        XCTAssertTrue(UserInterestTelemetryManager.canAcceptSyncAck(
            responseData: validAck,
            statusCode: 200,
            expectedDeviceID: "DEV-1",
            expectedBatchID: "batch-abc"
        ))
        XCTAssertFalse(UserInterestTelemetryManager.canAcceptSyncAck(
            responseData: validAck,
            statusCode: 500,
            expectedDeviceID: "dev-1",
            expectedBatchID: "batch-abc"
        ))
        XCTAssertFalse(UserInterestTelemetryManager.canAcceptSyncAck(
            responseData: validAck,
            statusCode: 200,
            expectedDeviceID: "other-dev",
            expectedBatchID: "batch-abc"
        ))

        var sent = TelemetryLocalStore()
        sent.stationHistory["magenta"] = TelemetryStationEntry(
            name: "Magenta", vtID: nil, rfiID: nil,
            viewCount: 3, searchCount: 1,
            firstSeen: "2026-11-27T08:00:00Z", lastSeen: "2026-11-27T09:00:00Z",
            daysSeen: ["2026-11-27"], hoursHistogram: ["8": 3], weekdaysHistogram: ["6": 3],
            gpsConfirmedCount: 1, lastLat: nil, lastLon: nil
        )
        sent.lineHistory["s6"] = TelemetryLineEntry(
            lineID: "S6", code: "S6", name: "Novara - Pioltello", kind: "Suburbana", region: "Lombardia",
            viewCount: 2, firstSeen: "2026-11-27T08:00:00Z", lastSeen: "2026-11-27T08:30:00Z",
            daysSeen: ["2026-11-27"], hoursHistogram: ["8": 2], weekdaysHistogram: ["6": 2]
        )

        // Exact match -> completely cleared
        let cleared = UserInterestTelemetryManager.subtractAcknowledgedStore(sent: sent, from: sent)
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertNil(cleared.pendingBatchID)

        // In-flight event arrives during sync -> only delta remains
        var current = sent
        current.stationHistory["magenta"]?.viewCount = 4
        current.stationHistory["magenta"]?.hoursHistogram["9"] = 1
        let remaining = UserInterestTelemetryManager.subtractAcknowledgedStore(sent: sent, from: current)
        XCTAssertFalse(remaining.isEmpty)
        XCTAssertEqual(remaining.stationHistory["magenta"]?.viewCount, 1)
        XCTAssertEqual(remaining.stationHistory["magenta"]?.hoursHistogram, ["9": 1])
        XCTAssertNil(remaining.lineHistory["s6"])
    }

    func testProactiveHabitPlanCacheAdvancesLocallyUntilLastSolutionDeparts() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        func romeDate(hour: Int, minute: Int) -> Date {
            var comps = DateComponents()
            comps.year = 2026; comps.month = 11; comps.day = 27
            comps.hour = hour; comps.minute = minute
            return cal.date(from: comps)!
        }

        let alt1 = PlanBAlternativeItem(
            train_number: "24631", category: "S6", destination: "Magenta",
            station: "Milano Porta Garibaldi", departure_time: "13:15", arrival_time: "13:50",
            duration: "35 min", delay: 0, platform: "1", transfer_info: "Diretto", legs: nil
        )
        let alt2 = PlanBAlternativeItem(
            train_number: "24633", category: "S6", destination: "Magenta",
            station: "Milano Porta Garibaldi", departure_time: "13:45", arrival_time: "14:20",
            duration: "35 min", delay: 5, platform: "1", transfer_info: "Diretto", legs: nil
        )
        let alt3 = PlanBAlternativeItem(
            train_number: "24635", category: "S6", destination: "Magenta",
            station: "Milano Porta Garibaldi", departure_time: "14:46", arrival_time: "15:21",
            duration: "35 min", delay: 0, platform: "1", transfer_info: "Diretto", legs: nil
        )
        let plan = PlanBReportDTO(
            title: "Ritorno abituale", body: "", incident_type: "simulation",
            incident_detail: nil, cancelled_train: nil, target_time: "13:00 - 14:50",
            origins: ["Milano Porta Garibaldi"], destinations: ["Magenta"],
            alternatives: [alt1, alt2, alt3], timestamp: "2026-11-27T13:00:00Z"
        )
        let dayKey = "2026-11-27"

        // At 13:05 all 3 are upcoming
        let at1305 = romeDate(hour: 13, minute: 5)
        XCTAssertTrue(SupporterCommuteManager.hasValidUpcomingCachedSolutions(plan: plan, dayKey: dayKey, at: at1305))
        XCTAssertEqual(SupporterCommuteManager.upcomingAlternatives(in: plan, at: at1305).map(\.train_number), ["24631", "24633", "24635"])

        // At 13:47 alt1 departed, alt2 still upcoming thanks to +5' delay (13:50), alt3 upcoming
        let at1347 = romeDate(hour: 13, minute: 47)
        XCTAssertTrue(SupporterCommuteManager.hasValidUpcomingCachedSolutions(plan: plan, dayKey: dayKey, at: at1347))
        XCTAssertEqual(SupporterCommuteManager.upcomingAlternatives(in: plan, at: at1347).map(\.train_number), ["24633", "24635"])

        // At 14:10 only alt3 (14:46) remains -> cache still valid, NO server refetch needed
        let at1410 = romeDate(hour: 14, minute: 10)
        XCTAssertTrue(SupporterCommuteManager.hasValidUpcomingCachedSolutions(plan: plan, dayKey: dayKey, at: at1410))
        XCTAssertEqual(SupporterCommuteManager.upcomingAlternatives(in: plan, at: at1410).map(\.train_number), ["24635"])

        // At 14:55 all solutions have departed -> cache expires cleanly
        let at1455 = romeDate(hour: 14, minute: 55)
        XCTAssertFalse(SupporterCommuteManager.hasValidUpcomingCachedSolutions(plan: plan, dayKey: dayKey, at: at1455))
        XCTAssertTrue(SupporterCommuteManager.upcomingAlternatives(in: plan, at: at1455).isEmpty)

        // Different day invalidates cache immediately
        XCTAssertFalse(SupporterCommuteManager.hasValidUpcomingCachedSolutions(plan: plan, dayKey: "2026-11-26", at: at1305))
    }

    func testHomeTrainSelectionDropsArrivedKeepsChronologicalOrderAndAlerts() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        func romeDate(hour: Int, minute: Int) -> Date {
            var comps = DateComponents()
            comps.year = 2026; comps.month = 11; comps.day = 27 // Venerdì (ISO 5)
            comps.hour = hour; comps.minute = minute
            return cal.date(from: comps)!
        }

        func makeSnap(num: String, dep: String, arr: String, delay: Int = 0, departed: Bool = false, arrived: Bool = false, cancelled: Bool = false) -> TrainLiveSnapshot {
            let s1 = Stop(stationName: "A", time: dep, actualTime: departed ? dep : nil, delay: delay, estimatedTime: nil, plannedPlatform: "1", actualPlatform: nil, isSuppressed: cancelled)
            let s2 = Stop(stationName: "B", time: arr, actualTime: arrived ? arr : nil, delay: delay, estimatedTime: nil, plannedPlatform: "2", actualPlatform: nil, isSuppressed: cancelled)
            return TrainLiveSnapshot(
                trainNumber: num, category: "S6", origin: "A", destination: "B",
                stops: [s1, s2], status: TrainStatus(),
                delayMinutes: delay, isCancelled: cancelled, isArrived: arrived, isDeparted: departed,
                lastStation: nil, lastTime: nil, nextStation: nil, nextEstimatedTime: nil,
                progress: arrived ? 1.0 : (departed ? 0.5 : 0.0), fetchedAt: Date()
            )
        }

        let tArrived = SavedTrain(number: "1001", description: "A - B", departureTime: "07:30", arrivalTime: "08:10")
        let tInTransit = SavedTrain(number: "1002", description: "A - B", departureTime: "08:15", arrivalTime: "09:00")
        let tSoonDelayed = SavedTrain(number: "1003", description: "A - B", departureTime: "09:10", arrivalTime: "09:50")
        let tSoonRegular = SavedTrain(number: "1004", description: "A - B", departureTime: "09:40", arrivalTime: "10:20")
        let tEvening1 = SavedTrain(number: "2001", description: "B - A", departureTime: "18:15", arrivalTime: "18:55")
        let tEvening2 = SavedTrain(number: "2002", description: "B - A", departureTime: "18:45", arrivalTime: "19:25")

        // Inserted out of chronological order to verify stable chronological output
        let favorites = [tEvening2, tSoonRegular, tArrived, tSoonDelayed, tInTransit, tEvening1]

        // Scenario 1: At 08:30 -> tArrived is GONE immediately; tInTransit + tSoonDelayed (+20') + tSoonRegular selected in chronological order, orange triangle!
        let snaps1: [String: TrainLiveSnapshot] = [
            "1001": makeSnap(num: "1001", dep: "07:30", arr: "08:10", departed: true, arrived: true),
            "1002": makeSnap(num: "1002", dep: "08:15", arr: "09:00", delay: 0, departed: true, arrived: false),
            "1003": makeSnap(num: "1003", dep: "09:10", arr: "09:50", delay: 20, departed: false, arrived: false),
            "1004": makeSnap(num: "1004", dep: "09:40", arr: "10:20", delay: 0, departed: false, arrived: false)
        ]
        let sel1 = TrainManager.selectHomeTrains(favoriteTrains: favorites, snapshots: snaps1, now: romeDate(hour: 8, minute: 30))
        XCTAssertTrue(sel1.hasActiveWindowTrains)
        XCTAssertEqual(sel1.trains.map(\.number), ["1002", "1003", "1004"]) // chronological 08:15 -> 09:10 -> 09:40, NOT shuffled by delay!
        XCTAssertEqual(sel1.alertSeverity, .warning) // > 15 min delay -> orange triangle

        // Scenario 2: Cancelled train near departure -> red triangle & guaranteed included in chronological order
        var snaps2 = snaps1
        snaps2["1004"] = makeSnap(num: "1004", dep: "09:40", arr: "10:20", cancelled: true)
        let sel2 = TrainManager.selectHomeTrains(favoriteTrains: favorites, snapshots: snaps2, now: romeDate(hour: 8, minute: 30))
        XCTAssertEqual(sel2.alertSeverity, .critical) // cancelled -> red triangle
        XCTAssertEqual(sel2.trains.map(\.number), ["1002", "1003", "1004"])

        // Scenario 3: Outside all active windows (14:00) -> fallback shows next 2 upcoming (18:15, 18:45) in chronological order, no alert
        let sel3 = TrainManager.selectHomeTrains(favoriteTrains: favorites, snapshots: [:], now: romeDate(hour: 14, minute: 0))
        XCTAssertFalse(sel3.hasActiveWindowTrains)
        XCTAssertEqual(sel3.trains.map(\.number), ["2001", "2002"])
        XCTAssertEqual(sel3.alertSeverity, .none)

        // Scenario 4: Consistent chronological sorting for full Trains tab & SavedTrips
        let allSorted = TrainManager.sortedTrainsByDeparture(favorites, snapshots: snaps1)
        XCTAssertEqual(allSorted.map(\.number), ["1001", "1002", "1003", "1004", "2001", "2002"])

        let tripLate = SavedTrip(id: "t2", origin: "A", destination: "B", departureTime: "18:30", arrivalTime: "19:10", duration: "40m", segments: [])
        let tripEarly = SavedTrip(id: "t1", origin: "A", destination: "B", departureTime: "08:05", arrivalTime: "08:45", duration: "40m", segments: [])
        XCTAssertEqual(TrainManager.sortedSavedTripsByDeparture([tripLate, tripEarly]).map(\.id), ["t1", "t2"])

        // Scenario 5: Home stations skip GPS duplicate already shown in "Per te"
        let s1 = Station(name: "Magenta", rfiID: nil, vtID: "S01025", lat: nil, lon: nil)
        let s2 = Station(name: "Milano Centrale", rfiID: nil, vtID: "S01700", lat: nil, lon: nil)
        let s3 = Station(name: "Rho Fiera", rfiID: nil, vtID: "S01039", lat: nil, lon: nil)
        let s4 = Station(name: "Milano Porta Garibaldi", rfiID: nil, vtID: "S01645", lat: nil, lon: nil)
        let homeSt = TrainManager.selectHomeStations(myStations: [s1, s2, s3, s4], excludingNearby: s1, maxCount: 3)
        XCTAssertEqual(homeSt.map(\.name), ["Milano Centrale", "Rho Fiera", "Milano Porta Garibaldi"])
    }

    @MainActor
    func testHomeSectionMaxItemsWidgetExclusionKeyAndIndividualUnignore() {
        let defaults = UserDefaults.standard
        let savedMaxItems = defaults.object(forKey: "homeSectionMaxItems_v1")
        defer {
            if let savedMaxItems {
                defaults.set(savedMaxItems, forKey: "homeSectionMaxItems_v1")
            } else {
                defaults.removeObject(forKey: "homeSectionMaxItems_v1")
            }
        }
        defaults.removeObject(forKey: "homeSectionMaxItems_v1")

        // 1. Per-section max items default (4 for stations, 3 for others), independent customization & 1...10 clamping
        let tm = TrainManager()
        XCTAssertEqual(tm.homeMaxItems(for: .myStations), 4)
        XCTAssertEqual(tm.homeMaxItems(for: .favoriteTrains), 3)
        XCTAssertEqual(tm.homeMaxItems(for: .favoriteRoutes), 3)
        XCTAssertEqual(tm.homeMaxItems(for: .passante), 3)

        // 1b. Hidden stations overflow summary ("+N stazioni" / "+N stazioni · M con avvisi")
        let hiddenSt1 = Station(name: "Magenta", rfiID: "1564", vtID: "S01025", lat: nil, lon: nil)
        let hiddenSt2 = Station(name: "Rho", rfiID: "2345", vtID: "S01037", lat: nil, lon: nil)
        let hiddenSt3 = Station(name: "Milano Certosa", rfiID: "1708", vtID: "S01640", lat: nil, lon: nil)
        XCTAssertNil(TrainManager.homeHiddenStationsSummary(hiddenStations: [], snapshots: [:]))

        let oneRegular = TrainManager.homeHiddenStationsSummary(hiddenStations: [hiddenSt1], snapshots: [:])
        XCTAssertEqual(oneRegular?.text, "+1 stazione")
        XCTAssertEqual(oneRegular?.alertCount, 0)
        XCTAssertEqual(oneRegular?.hasCritical, false)

        let snapWarning = StationBoardSnapshot(
            stationKey: TrainManager.canonicalStationKey(for: hiddenSt2),
            stationName: hiddenSt2.name,
            circulationState: .warning,
            healthMessage: "Ritardi dir. Milano",
            averageDelayMinutes: 12,
            delayedCount: 2,
            cancelledCount: 0,
            trains: [],
            previewTrains: [],
            alerts: nil,
            fetchedAt: Date()
        )
        let snapDisrupted = StationBoardSnapshot(
            stationKey: TrainManager.canonicalStationKey(for: hiddenSt3),
            stationName: hiddenSt3.name,
            circulationState: .disrupted,
            healthMessage: "Soppressioni dir. Rho",
            averageDelayMinutes: 20,
            delayedCount: 1,
            cancelledCount: 2,
            trains: [],
            previewTrains: [],
            alerts: nil,
            fetchedAt: Date()
        )
        let threeOneAlert = TrainManager.homeHiddenStationsSummary(
            hiddenStations: [hiddenSt1, hiddenSt2, hiddenSt3],
            snapshots: [snapWarning.stationKey: snapWarning]
        )
        XCTAssertEqual(threeOneAlert?.text, "+3 stazioni · 1 con avvisi")
        XCTAssertEqual(threeOneAlert?.alertCount, 1)
        XCTAssertEqual(threeOneAlert?.hasCritical, false)

        let twoCritical = TrainManager.homeHiddenStationsSummary(
            hiddenStations: [hiddenSt2, hiddenSt3],
            snapshots: [snapWarning.stationKey: snapWarning, snapDisrupted.stationKey: snapDisrupted]
        )
        XCTAssertEqual(twoCritical?.text, "+2 stazioni · 2 con avvisi")
        XCTAssertEqual(twoCritical?.alertCount, 2)
        XCTAssertEqual(twoCritical?.hasCritical, true)

        tm.setHomeMaxItems(7, for: .favoriteTrains)
        tm.setHomeMaxItems(0, for: .myStations)   // clamps to 1
        tm.setHomeMaxItems(25, for: .passante)    // clamps to 10
        XCTAssertEqual(tm.homeMaxItems(for: .favoriteTrains), 7)
        XCTAssertEqual(tm.homeMaxItems(for: .myStations), 1)
        XCTAssertEqual(tm.homeMaxItems(for: .passante), 10)
        XCTAssertEqual(tm.homeMaxItems(for: .favoriteRoutes), 3)

        // Persists across fresh TrainManager instances
        let tmReloaded = TrainManager()
        XCTAssertEqual(tmReloaded.homeMaxItems(for: .favoriteTrains), 7)
        XCTAssertEqual(tmReloaded.homeMaxItems(for: .myStations), 1)
        XCTAssertEqual(tmReloaded.homeMaxItems(for: .passante), 10)

        // 2. Stable widget station exclusion keys (normalized name > vtID > rfiID, matching StationBoardWidget)
        let stName = Station(name: "  Milano Cadorna ", rfiID: "1705", vtID: "S01066", lat: nil, lon: nil)
        let stVtFallback = Station(name: "   ", rfiID: "1728", vtID: "S01700", lat: nil, lon: nil)
        let stRfiFallback = Station(name: "", rfiID: "3468", vtID: nil, lat: nil, lon: nil)
        XCTAssertEqual(TrainManager.widgetStationExclusionKey(for: stName), "milano cadorna")
        XCTAssertEqual(TrainManager.widgetStationExclusionKey(for: stVtFallback), "s01700")
        XCTAssertEqual(TrainManager.widgetStationExclusionKey(for: stRfiFallback), "3468")

        // 3. UsageTracker per-item unignore only removes the targeted suggestion
        let tracker = UsageTracker()
        tracker.unignoreAll()
        tracker.ignoreStation("Magenta")
        tracker.ignoreStation("Milano Centrale")
        tracker.ignoreTrain("24627")
        tracker.ignoreTrain("24629")
        tracker.ignoreRoute("830001025-830001700")
        tracker.ignoreRoute("830001037-830001650")

        tracker.unignoreStation("Magenta")
        XCTAssertEqual(tracker.ignoredStationNames, Set(["milano centrale"]))

        tracker.unignoreTrain("24627")
        XCTAssertEqual(tracker.ignoredTrainNumbers, Set(["24629"]))

        tracker.unignoreRoute("830001025-830001700")
        XCTAssertEqual(tracker.ignoredRouteKeys, Set(["830001037-830001650"]))

        tracker.unignoreAll()
    }

    @MainActor
    func testStationHealthIgnoresAVDelaysAutoUnpinOnArrivalAndHomeOpensAssistant() {
        // 1. Station health MUST ignore Alta Velocità delays when commuter trains are regular,
        //    and NEVER display "Forti Ritardi Alta Velocità" / "Alta Velocità" anywhere.
        let avDelayed = [
            Train(category: "FR", number: "9614", destination: "ROMA TERMINI", time: "09:00", delay: "+45'", platform: "1"),
            Train(category: "ITA", number: "9920", destination: "NAPOLI CENTRALE", time: "09:10", delay: "Soppresso", platform: "2"),
            Train(category: "S6", number: "24627", destination: "NOVARA", time: "09:15", delay: "In orario", platform: "3"),
            Train(category: "REG", number: "2019", destination: "TORINO PORTA NUOVA", time: "09:20", delay: "+4'", platform: "4")
        ]
        let mixedHealth = TrainManager.computeLineHealth(for: avDelayed)
        XCTAssertEqual(mixedHealth.state, .regular)
        XCTAssertEqual(mixedHealth.message, "Circolazione regolare")
        XCTAssertFalse(mixedHealth.message.localizedCaseInsensitiveContains("alta velocit"))

        // Even on a pure-AV board, message never mentions "Alta Velocità"
        let pureAVDisrupted = [
            Train(category: "FR", number: "9614", destination: "ROMA TERMINI", time: "09:00", delay: "+40'", platform: "1"),
            Train(category: "FR", number: "9616", destination: "NAPOLI CENTRALE", time: "09:15", delay: "+35'", platform: "2")
        ]
        let pureAVHealth = TrainManager.computeLineHealth(for: pureAVDisrupted)
        XCTAssertEqual(pureAVHealth.state, .warning)
        XCTAssertFalse(pureAVHealth.message.localizedCaseInsensitiveContains("alta velocit"))

        // Regional cancellations & severe delays are properly reported with directions
        let regCancellations = [
            Train(category: "S6", number: "24627", destination: "NOVARA", time: "09:15", delay: "Soppresso", platform: "1"),
            Train(category: "S6", number: "24629", destination: "NOVARA", time: "09:45", delay: "Cancellato", platform: "1"),
            Train(category: "REG", number: "2019", destination: "TORINO PORTA NUOVA", time: "09:20", delay: "In orario", platform: "2")
        ]
        let regCancHealth = TrainManager.computeLineHealth(for: regCancellations)
        XCTAssertEqual(regCancHealth.state, .disrupted)
        XCTAssertEqual(regCancHealth.message, "Soppressioni dir. Novara")

        // 2. Live Activity auto-unpin when train arrives at destination
        let stopA = Stop(stationName: "Magenta", time: "08:00", actualTime: "08:01", delay: 1, estimatedTime: nil, plannedPlatform: "1", actualPlatform: "1", isSuppressed: false)
        let stopBPending = Stop(stationName: "Milano Centrale", time: "08:40", actualTime: nil, delay: 1, estimatedTime: "08:41", plannedPlatform: "2", actualPlatform: nil, isSuppressed: false)
        let stopBArrived = Stop(stationName: "Milano Centrale", time: "08:40", actualTime: "08:41", delay: 1, estimatedTime: "08:41", plannedPlatform: "2", actualPlatform: "2", isSuppressed: false)

        var inTransitStatus = TrainStatus()
        inTransitStatus.isDeparted = true
        inTransitStatus.isArrived = false
        inTransitStatus.statusMessage = "In viaggio (+1')"
        XCTAssertFalse(TrainManager.shouldAutoEndLiveActivity(stops: [stopA, stopBPending], status: inTransitStatus))

        var arrivedStatus = TrainStatus()
        arrivedStatus.isDeparted = true
        arrivedStatus.isArrived = true
        arrivedStatus.statusMessage = "Arrivato"
        XCTAssertTrue(TrainManager.shouldAutoEndLiveActivity(stops: [stopA, stopBPending], status: arrivedStatus))
        XCTAssertTrue(TrainManager.shouldAutoEndLiveActivity(stops: [stopA, stopBArrived], status: inTransitStatus))

        // 3. Opening Search from Home opens the Assistant (without forcing mic on)
        let coordinator = MainNavigationCoordinator(launchTabRawValue: MainTab.home.rawValue)
        coordinator.openContextualSearch(for: .home)
        XCTAssertEqual(coordinator.activeSearchRequest?.initialAssistantMode, true)
        XCTAssertEqual(coordinator.activeSearchRequest?.autoStartVoice, false)

        coordinator.openContextualSearch(for: .stations)
        XCTAssertEqual(coordinator.activeSearchRequest?.initialAssistantMode, false)
        XCTAssertEqual(coordinator.activeSearchRequest?.scope, .trainsAndStations)

        coordinator.openContextualSearch(for: .trips)
        XCTAssertEqual(coordinator.activeSearchRequest?.initialAssistantMode, false)
        XCTAssertEqual(coordinator.activeSearchRequest?.scope, .solutions)
    }

    @MainActor
    func testTravelSolutions30MinuteRouteCacheHitExpirationAndDateMismatch() {
        let now = Date(timeIntervalSince1970: 1_764_260_000)
        let sampleSolution = TravelSolution(
            trainNumber: "24627",
            category: "S6",
            departureTime: "08:15",
            arrivalTime: "08:50",
            origin: "Magenta",
            destination: "Milano Porta Garibaldi",
            duration: "35 min",
            segments: [
                TravelSegment(
                    origin: "Magenta",
                    destination: "Milano Porta Garibaldi",
                    departureTime: "08:15",
                    arrivalTime: "08:50",
                    trainNumber: "24627",
                    trainCategory: "S6",
                    travelMinutes: 35
                )
            ]
        )

        let entry = CachedTravelSolutionsEntry(
            originID: "830001025",
            destID: "830001645",
            resolvedOriginID: "830001025",
            resolvedDestID: "830001645",
            requestedDate: now,
            fetchedAt: now,
            solutions: [CachedTravelSolutionDTO(from: sampleSolution)]
        )

        // 1. Within 30 minutes and same requested time window -> cache hit
        let hit = TrainManager.cachedSolutionsIfValid(
            entry: entry,
            requestedDate: now.addingTimeInterval(10 * 60),
            now: now.addingTimeInterval(20 * 60)
        )
        XCTAssertEqual(hit?.count, 1)
        XCTAssertEqual(hit?.first?.trainNumber, "24627")

        // 2. After 31 minutes -> cache expired
        let expired = TrainManager.cachedSolutionsIfValid(
            entry: entry,
            requestedDate: now.addingTimeInterval(31 * 60),
            now: now.addingTimeInterval(31 * 60)
        )
        XCTAssertNil(expired)

        // 3. Within 30 min fetch age, but user manually changed departure time by +2 hours -> cache miss
        let differentTime = TrainManager.cachedSolutionsIfValid(
            entry: entry,
            requestedDate: now.addingTimeInterval(120 * 60),
            now: now.addingTimeInterval(5 * 60)
        )
        XCTAssertNil(differentTime)

        // 4. Reverse direction produces a distinct cache key
        XCTAssertNotEqual(
            TrainManager.travelSolutionsRouteKey(originID: "830001025", destID: "830001645"),
            TrainManager.travelSolutionsRouteKey(originID: "830001645", destID: "830001025")
        )
    }

    @MainActor
    func testPerformanceCatalogBoundingBoxOriginCacheAndLazyTabs() {
        // 1. Shared RFIStationCatalog loads once and fast bounding-box lookup matches Milano Centrale accurately
        let rfiCount = RFIStationCatalog.shared.rfiStations.count
        XCTAssertGreaterThan(rfiCount, 3000)
        let geoStations = RFIStationCatalog.shared.geoStations
        XCTAssertFalse(geoStations.isEmpty)

        let nearCentrale = CLLocation(latitude: 45.4859, longitude: 9.2043)
        let closest = RFIStationCatalog.nearestStation(to: nearCentrale, in: geoStations, maxDistanceMeters: 4000)
        XCTAssertEqual(closest?.station.name, "MILANO CENTRALE")
        XCTAssertLessThan(closest?.distance ?? 9999, 500)

        let middleOfSea = CLLocation(latitude: 40.0, longitude: 11.0)
        XCTAssertNil(RFIStationCatalog.nearestStation(to: middleOfSea, in: geoStations, maxDistanceMeters: 4000))

        // 2. Daily train origin resolution keys & Rome calendar day formatting
        let fixedDate = Date(timeIntervalSince1970: 1_764_260_000) // 2025-11-27
        let dayKey = TrainRepository.currentRomeDayKey(for: fixedDate)
        XCTAssertEqual(dayKey, "2025-11-27")
        let keys = TrainRepository.originResolutionKeys(
            dayKey: dayKey,
            cleanNumber: "24627",
            destination: " Novara ",
            origin: " Pioltello-Limito "
        )
        XCTAssertEqual(keys.generic, "2025-11-27|24627")
        XCTAssertEqual(keys.specific, "2025-11-27|24627|PIOLTELLO-LIMITO|NOVARA")

        // 3. Lazy tab mounting: only initial + home mounted at boot, switching tab mounts target
        let coordinator = MainNavigationCoordinator(launchTabRawValue: MainTab.home.rawValue)
        XCTAssertEqual(coordinator.mountedTabs, [.home])
        XCTAssertFalse(coordinator.mountedTabs.contains(.lines))
        coordinator.selectedTab = .lines
        XCTAssertTrue(coordinator.mountedTabs.contains(.lines))
    }

    @MainActor
    func testOnboardingCampaignLaunchDecisionAndConditionalPermissions() {
        // 1. Launch decision: brand new user -> full onboarding
        XCTAssertEqual(
            OnboardingLaunchDecision.resolve(hasCompletedOnboarding: false, lastSeenUpdateID: ""),
            .showFullOnboarding
        )

        // 2. Existing user upgrading from older version -> What's New update onboarding once
        XCTAssertEqual(
            OnboardingLaunchDecision.resolve(hasCompletedOnboarding: true, lastSeenUpdateID: ""),
            .showUpdateOnboarding
        )
        XCTAssertEqual(
            OnboardingLaunchDecision.resolve(hasCompletedOnboarding: true, lastSeenUpdateID: "older_campaign"),
            .showUpdateOnboarding
        )

        // 3. Existing user who already saw current campaign -> no onboarding
        XCTAssertEqual(
            OnboardingLaunchDecision.resolve(
                hasCompletedOnboarding: true,
                lastSeenUpdateID: OnboardingCampaign.currentUpdateID
            ),
            .none
        )

        // 4. Permission snapshot: both active -> skip permissions step
        let bothActive = OnboardingPermissionSnapshot.from(
            notificationStatus: .authorized,
            remoteNotificationsEnabled: true,
            locationStatus: .authorizedWhenInUse
        )
        XCTAssertFalse(bothActive.needsNotifications)
        XCTAssertFalse(bothActive.needsLocation)
        XCTAssertFalse(bothActive.needsAnyPermission)

        // 5. System authorized but in-app notification toggle OFF -> needs notifications
        let appToggleOff = OnboardingPermissionSnapshot.from(
            notificationStatus: .authorized,
            remoteNotificationsEnabled: false,
            locationStatus: .authorizedAlways
        )
        XCTAssertEqual(appToggleOff.notifications, .authorizedAppToggleOff)
        XCTAssertTrue(appToggleOff.needsNotifications)
        XCTAssertFalse(appToggleOff.needsLocation)
        XCTAssertTrue(appToggleOff.needsAnyPermission)

        // 6. Notifications denied, location ok -> needs notifications
        let notifDenied = OnboardingPermissionSnapshot.from(
            notificationStatus: .denied,
            remoteNotificationsEnabled: false,
            locationStatus: .authorizedWhenInUse
        )
        XCTAssertEqual(notifDenied.notifications, .denied)
        XCTAssertTrue(notifDenied.needsNotifications)
        XCTAssertFalse(notifDenied.needsLocation)

        // 7. Provisional notifications OK, location denied -> needs location
        let locDenied = OnboardingPermissionSnapshot.from(
            notificationStatus: .provisional,
            remoteNotificationsEnabled: true,
            locationStatus: .denied
        )
        XCTAssertFalse(locDenied.needsNotifications)
        XCTAssertEqual(locDenied.location, .deniedOrRestricted)
        XCTAssertTrue(locDenied.needsLocation)

        // 8. Both notDetermined -> needs both
        let bothUnset = OnboardingPermissionSnapshot.from(
            notificationStatus: .notDetermined,
            remoteNotificationsEnabled: false,
            locationStatus: .notDetermined
        )
        XCTAssertTrue(bothUnset.needsNotifications)
        XCTAssertTrue(bothUnset.needsLocation)
        XCTAssertTrue(bothUnset.needsAnyPermission)

        // 9. Dynamic step sequences across modes, regions, and permission state
        XCTAssertEqual(
            OnboardingStep.steps(for: .updateWhatsNew, strikeRegion: "Lombardia", includePermissionsStep: false),
            [.whatsNew, .quickGuide]
        )
        XCTAssertEqual(
            OnboardingStep.steps(for: .updateWhatsNew, strikeRegion: "Lazio", includePermissionsStep: true),
            [.whatsNew, .permissions, .quickGuide]
        )
        XCTAssertEqual(
            OnboardingStep.steps(for: .fullFirstLaunch, strikeRegion: "Lombardia", includePermissionsStep: true),
            [.welcome, .permissions, .region, .passante, .stations, .quickGuide]
        )
        XCTAssertEqual(
            OnboardingStep.steps(for: .fullFirstLaunch, strikeRegion: "Lazio", includePermissionsStep: false),
            [.welcome, .region, .stations, .quickGuide]
        )

        // 10. Verify Free scheduled notification limit remains 10
        XCTAssertEqual(TrainManager.freeScheduledNotificationLimit, 10)
    }

    @MainActor
    func testUnifiedCommuteDirectionMaxStationsAndLocalMultiStationAggregator() {
        // 1. Max 3+3 station cap applies ONLY to Free users; Pro users have no 3-station cap
        XCTAssertEqual(SupporterCommuteManager.maxStationsPerSide, 3)
        XCTAssertTrue(SupporterCommuteManager.canAddStation(currentCount: 2, isPro: false))
        XCTAssertFalse(SupporterCommuteManager.canAddStation(currentCount: 3, isPro: false))
        XCTAssertTrue(SupporterCommuteManager.canAddStation(currentCount: 3, isPro: true))
        XCTAssertTrue(SupporterCommuteManager.canAddStation(currentCount: 6, isPro: true))

        // 1b. Onboarding audience differentiates Pro vs Free before display
        XCTAssertEqual(OnboardingAudience.resolve(hasSupport: false), .free)
        XCTAssertEqual(OnboardingAudience.resolve(hasSupport: true), .pro)

        // 2. Time-based automatic direction selection (Europe/Rome)
        var romeCal = Calendar(identifier: .gregorian)
        romeCal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let morningDate = romeCal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 7, minute: 30))!
        let lateMorningDate = romeCal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 11, minute: 0))!
        let afternoonDate = romeCal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 13, minute: 30))!
        let eveningDate = romeCal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 17, minute: 45))!

        XCTAssertFalse(SupporterCommuteManager.preferredIsReturn(at: morningDate, outboundBand: "07:00 - 08:00", returnBand: "17:00 - 18:00"))
        XCTAssertFalse(SupporterCommuteManager.preferredIsReturn(at: lateMorningDate, outboundBand: "07:00 - 08:00", returnBand: "17:00 - 18:00"))
        XCTAssertTrue(SupporterCommuteManager.preferredIsReturn(at: afternoonDate, outboundBand: "07:00 - 08:00", returnBand: "17:00 - 18:00"))
        XCTAssertTrue(SupporterCommuteManager.preferredIsReturn(at: eveningDate, outboundBand: "07:00 - 08:00", returnBand: "17:00 - 18:00"))

        // 3. AV corridor detection
        XCTAssertFalse(CommuteTrainDiscoveryService.isAVCommuteCorridor(
            origins: ["Magenta", "Corbetta-S. Stefano"],
            destinations: ["Milano Centrale", "Milano Porta Garibaldi"]
        ))
        XCTAssertTrue(CommuteTrainDiscoveryService.isAVCommuteCorridor(
            origins: ["Bologna Centrale"],
            destinations: ["Milano Centrale"]
        ))

        // 4. Local multi-station deduplication: direct beats transfer & collapses multiple direct destinations
        let transferCandidate = PlanBAlternativeItem(
            train_number: "24627",
            category: "S6",
            destination: "Milano Centrale",
            station: "Magenta",
            departure_time: "08:04",
            arrival_time: "08:55",
            duration: "51min",
            delay: 0,
            platform: "1",
            transfer_info: "1 cambio",
            legs: [
                PlanBLegItem(train_number: "24627", category: "S6", origin: "Magenta", destination: "Milano Porta Garibaldi", departure_time: "08:04", arrival_time: "08:39", delay: 0, platform: "1", is_urban: false, is_station_walk: false),
                PlanBLegItem(train_number: "M2", category: "Trasporto Urbano", origin: "Milano Porta Garibaldi", destination: "Milano Centrale", departure_time: "08:45", arrival_time: "08:55", delay: 0, platform: "--", is_urban: true, is_station_walk: false)
            ]
        )
        let directGaribaldi = PlanBAlternativeItem(
            train_number: "24627",
            category: "S6",
            destination: "Milano Porta Garibaldi",
            station: "Magenta",
            departure_time: "08:04",
            arrival_time: "08:39",
            duration: "35min",
            delay: 0,
            platform: "1",
            transfer_info: "Treno diretto",
            legs: [
                PlanBLegItem(train_number: "24627", category: "S6", origin: "Magenta", destination: "Milano Porta Garibaldi", departure_time: "08:04", arrival_time: "08:39", delay: 0, platform: "1", is_urban: false, is_station_walk: false)
            ]
        )
        let directRepubblica = PlanBAlternativeItem(
            train_number: "24627",
            category: "S6",
            destination: "Milano Repubblica",
            station: "Magenta",
            departure_time: "08:04",
            arrival_time: "08:42",
            duration: "38min",
            delay: 0,
            platform: "1",
            transfer_info: "Treno diretto",
            legs: [
                PlanBLegItem(train_number: "24627", category: "S6", origin: "Magenta", destination: "Milano Repubblica", departure_time: "08:04", arrival_time: "08:42", delay: 0, platform: "1", is_urban: false, is_station_walk: false)
            ]
        )

        let ranked = CommuteTrainDiscoveryService.deduplicateAndRankAlternatives(
            [transferCandidate, directRepubblica, directGaribaldi],
            configuredOrigins: ["Magenta"],
            configuredDestinations: ["Milano Centrale", "Milano Porta Garibaldi", "Milano Repubblica"]
        )
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked[0].resolvedLegs.count, 1)
        XCTAssertEqual(ranked[0].destination, "Milano Porta Garibaldi")
        XCTAssertTrue(ranked[0].transfer_info.contains("Repubblica"))
    }
}
