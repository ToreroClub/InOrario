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
}
